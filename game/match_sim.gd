class_name MatchSim
extends RefCounted

## Simulación autoritativa del combate. Se ejecuta SOLO en el servidor.
## Física a mano (sin CharacterBody2D) para tener control total y resultados estables.

const WORLD := Vector2(320.0, 180.0)
const WATER_Y := 165.0
const PLAYER_HALF := Vector2(5.0, 7.0)

# --- Física de vuelo -------------------------------------------------------
const GRAVITY_NORMAL := 760.0
const GRAVITY_LOW := 1180.0          # con 1 globo cae más rápido
const MAX_FALL_NORMAL := 380.0
const MAX_FALL_LOW := 470.0
const FLAP_VEL_NORMAL := -300.0
const FLAP_VEL_LOW := -235.0         # con 1 globo alcanza menos altura
const FLAP_COOLDOWN := 0.34
const MOVE_SPEED := 115.0
const MOVE_ACCEL := 980.0
const AIR_FRICTION := 340.0
const GROUND_FRICTION := 1500.0

# --- Combate ---------------------------------------------------------------
const KNOCKBACK_X := 360.0
const KNOCKBACK_Y := -170.0
const MELEE_RANGE := 30.0
const MELEE_COOLDOWN := 0.55
const STOMP_BOUNCE := -120.0

# --- Peligros --------------------------------------------------------------
const LIGHTNING_INTERVAL := 20.0

const BALLOON_LEFT := Vector2(-6.0, -13.0)
const BALLOON_RIGHT := Vector2(6.0, -13.0)

class PlayerState:
	var pid: int = 0
	var slot: int = 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var globos := 2
	var balloons: Array[bool] = [true, true]
	var alive := true
	var facing := 1
	var on_ground := false
	var flap_cd := 0.0
	var melee_cd := 0.0
	var input_x := 0.0
	var input_flap := false
	var input_attack := false

var seed_value := 0
var platforms: Array[Rect2] = []
var spawns: Array[Vector2] = []
var clouds: Array[Rect2] = []
var players: Array = []

var time := 0.0
var since_damage := 0.0
var over := false
var winner_pid := -1

var _events: Array = []
var _rng := RandomNumberGenerator.new()


static func balloon_offset(index: int) -> Vector2:
	return BALLOON_LEFT if index == 0 else BALLOON_RIGHT


func setup(new_seed: int, player_pids: Array) -> void:
	seed_value = new_seed
	var map := MapGen.generate(new_seed)
	platforms = map["platforms"]
	spawns = map["spawns"]
	clouds = map["clouds"]

	players.clear()
	var idx := 0
	for pid in player_pids:
		if idx >= spawns.size():
			break
		var p := PlayerState.new()
		p.pid = int(pid)
		p.slot = idx
		p.pos = spawns[idx]
		p.facing = 1 if idx == 0 else -1
		players.append(p)
		idx += 1

	over = false
	winner_pid = -1
	time = 0.0
	since_damage = 0.0
	_events.clear()
	_rng.seed = new_seed * 31 + 7


func get_player(pid: int) -> PlayerState:
	for p in players:
		if p.pid == pid:
			return p
	return null


func set_input(pid: int, mx: float, flap: bool, attack: bool) -> void:
	var p := get_player(pid)
	if p == null:
		return
	p.input_x = clampf(mx, -1.0, 1.0)
	p.input_flap = flap
	p.input_attack = attack


func step(dt: float) -> void:
	if over:
		return
	time += dt
	since_damage += dt

	for p in players:
		if p.alive:
			_update_player(p, dt)

	if over:
		return

	if since_damage >= LIGHTNING_INTERVAL:
		_strike_lightning()


func drain_events() -> Array:
	var out := _events
	_events = []
	return out


# ---------------------------------------------------------------------------
# Física
# ---------------------------------------------------------------------------

func _update_player(p: PlayerState, dt: float) -> void:
	p.flap_cd = maxf(0.0, p.flap_cd - dt)
	p.melee_cd = maxf(0.0, p.melee_cd - dt)

	var gravity := GRAVITY_NORMAL
	var max_fall := MAX_FALL_NORMAL
	if p.globos <= 1:
		gravity = GRAVITY_LOW
		max_fall = MAX_FALL_LOW

	# Inercia horizontal: acelera hacia la dirección, frena gradualmente.
	if absf(p.input_x) > 0.15:
		p.facing = 1 if p.input_x > 0.0 else -1
		p.vel.x = move_toward(p.vel.x, p.input_x * MOVE_SPEED, MOVE_ACCEL * dt)
	else:
		var friction := GROUND_FRICTION if p.on_ground else AIR_FRICTION
		p.vel.x = move_toward(p.vel.x, 0.0, friction * dt)

	# Aleteo: impulso finito con cooldown corto (se puede mantener pulsado).
	if p.input_flap and p.flap_cd <= 0.0:
		p.flap_cd = FLAP_COOLDOWN
		p.vel.y = FLAP_VEL_NORMAL if p.globos >= 2 else FLAP_VEL_LOW

	p.vel.y = minf(p.vel.y + gravity * dt, max_fall)

	_integrate(p, dt)
	_check_water(p)

	if p.input_attack and p.melee_cd <= 0.0 and p.alive:
		p.melee_cd = MELEE_COOLDOWN
		_do_attack(p)


func _integrate(p: PlayerState, dt: float) -> void:
	var speed := maxf(absf(p.vel.x), absf(p.vel.y))
	var steps := clampi(int(ceil(speed * dt / 6.0)), 1, 8)
	var sdt := dt / float(steps)

	for i in range(steps):
		# Eje X
		p.pos.x += p.vel.x * sdt
		p.pos.x = clampf(p.pos.x, PLAYER_HALF.x, WORLD.x - PLAYER_HALF.x)
		var rect := Rect2(p.pos - PLAYER_HALF, PLAYER_HALF * 2.0)
		for plat in platforms:
			if rect.intersects(plat):
				if p.vel.x > 0.0:
					p.pos.x = plat.position.x - PLAYER_HALF.x
				elif p.vel.x < 0.0:
					p.pos.x = plat.position.x + plat.size.x + PLAYER_HALF.x
				p.vel.x = 0.0
				rect = Rect2(p.pos - PLAYER_HALF, PLAYER_HALF * 2.0)
				break

		# Eje Y
		p.on_ground = false
		p.pos.y += p.vel.y * sdt
		if p.pos.y < PLAYER_HALF.y:
			p.pos.y = PLAYER_HALF.y
			p.vel.y = 0.0
		rect = Rect2(p.pos - PLAYER_HALF, PLAYER_HALF * 2.0)
		for plat in platforms:
			if rect.intersects(plat):
				if p.vel.y >= 0.0:
					p.pos.y = plat.position.y - PLAYER_HALF.y
					p.on_ground = true
				else:
					p.pos.y = plat.position.y + plat.size.y + PLAYER_HALF.y
				p.vel.y = 0.0
				rect = Rect2(p.pos - PLAYER_HALF, PLAYER_HALF * 2.0)
				break


# ---------------------------------------------------------------------------
# Combate
# ---------------------------------------------------------------------------

func _do_attack(attacker: PlayerState) -> void:
	for other in players:
		if other == attacker or not other.alive:
			continue

		# Pisotón: cayendo sobre un globo enemigo desde arriba.
		if attacker.vel.y > 40.0:
			for i in range(other.balloons.size()):
				if not other.balloons[i]:
					continue
				var bpos: Vector2 = other.pos + balloon_offset(i)
				var dx := absf(bpos.x - attacker.pos.x)
				var dy := bpos.y - attacker.pos.y
				if dx < 10.0 and dy > 2.0 and dy < 20.0:
					_pop_balloon(other, "stomp")
					attacker.vel.y = STOMP_BOUNCE
					_events.append({"type": "stomp", "pid": attacker.pid, "victim": other.pid})
					return

		# Cuerpo a cuerpo: knockback horizontal (no revienta globos).
		if attacker.pos.distance_to(other.pos) < MELEE_RANGE:
			var dir := signf(other.pos.x - attacker.pos.x)
			if absf(dir) < 0.01:
				dir = float(attacker.facing)
			other.vel.x = dir * KNOCKBACK_X
			other.vel.y = minf(other.vel.y, KNOCKBACK_Y)
			_events.append({"type": "melee", "pid": attacker.pid, "victim": other.pid})
			return


func _pop_balloon(p: PlayerState, cause: String) -> void:
	if not p.alive:
		return
	var idx := -1
	for i in range(p.balloons.size() - 1, -1, -1):
		if p.balloons[i]:
			idx = i
			break
	if idx >= 0:
		p.balloons[idx] = false
	p.globos = maxi(0, p.globos - 1)
	since_damage = 0.0
	_events.append({"type": "balloon_pop", "pid": p.pid, "cause": cause, "pos": p.pos})

	if p.globos <= 0:
		p.alive = false
		over = true
		winner_pid = _other_pid(p.pid)
		_events.append({"type": "eliminated", "pid": p.pid, "winner": winner_pid})


func _other_pid(pid: int) -> int:
	for p in players:
		if p.pid != pid:
			return p.pid
	return -1


# ---------------------------------------------------------------------------
# Peligros
# ---------------------------------------------------------------------------

func _check_water(p: PlayerState) -> void:
	if p.pos.y + PLAYER_HALF.y < WATER_Y + 1.0:
		return
	_events.append({"type": "splash", "pid": p.pid, "pos": p.pos})
	_pop_balloon(p, "water")
	if p.alive:
		p.pos = spawns[p.slot]
		p.vel = Vector2.ZERO
		p.flap_cd = 0.0
		p.melee_cd = 0.0


func _strike_lightning() -> void:
	since_damage = 0.0
	var alive_players: Array = []
	for p in players:
		if p.alive and p.globos > 0:
			alive_players.append(p)
	if alive_players.is_empty():
		return
	var victim: PlayerState = alive_players[_rng.randi_range(0, alive_players.size() - 1)]
	_events.append({"type": "lightning", "pid": victim.pid, "pos": victim.pos})
	_pop_balloon(victim, "lightning")
	if victim.alive:
		victim.vel.y = -120.0

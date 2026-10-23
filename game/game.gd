extends Node2D

## Balloon Smash - MVP online (servidor autoritativo ENet).
##
## Servidor dedicado:  godot --headless --path . -- --server
## Cliente:            godot --path . -- --ip=127.0.0.1

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 2
const INTERP_TIME := 0.07
const TICK := 1.0 / 60.0

enum Phase { CONNECTING, WAITING, PLAYING, GAME_OVER, ERROR }

# --- Paleta pixel art -------------------------------------------------------
const COL_SKY_TOP := Color("#0b1026")
const COL_SKY_MID := Color("#101733")
const COL_SKY_LOW := Color("#172047")
const COL_STAR := Color("#93a7d8")
const COL_CLOUD := Color("#1b2550")
const COL_PLATFORM := Color("#1f5240")
const COL_PLATFORM_TOP := Color("#3f8f63")
const COL_PLATFORM_DARK := Color("#122f26")
const COL_WATER := Color("#0d2b55")
const COL_WATER_DARK := Color("#081c3a")
const COL_WATER_LINE := Color("#337cc4")
const COL_P1 := Color("#ef5350")
const COL_P1_LIGHT := Color("#ff9a94")
const COL_P2 := Color("#42a5f5")
const COL_P2_LIGHT := Color("#9ccbf7")
const COL_TEXT := Color("#e8eefc")
const COL_TEXT_DIM := Color("#8a97b8")
const COL_OUTLINE := Color("#0a0f1e")
const COL_BOLT := Color("#ffe082")

# --- Estado de red ----------------------------------------------------------
var is_server := false
var phase: Phase = Phase.CONNECTING
var _port := DEFAULT_PORT
var _online := false
var _retry_timer := 0.0
var _status := ""

var _local_pid := 0
var _peer_ids: Array = []
var _local_slot := 0
var _match_seed := 0

# --- Servidor ---------------------------------------------------------------
var _server_peers: Array = []
var _sim: MatchSim = null
var _accum := 0.0
var _winner := -1

# --- Cliente (visual) -------------------------------------------------------
var _platforms: Array[Rect2] = []
var _spawns: Array[Vector2] = []
var _clouds: Array[Rect2] = []
var _states := {}
var _fx: Array = []
var _stars: Array[Vector2] = []
var _time := 0.0
var _over_reason := ""

var _local_input := {"mx": 0.0, "flap": false, "attack": false}


func _ready() -> void:
	randomize()
	_setup_input()
	_build_stars()
	_port = _arg_int("--port=", DEFAULT_PORT)
	if _has_arg("--server"):
		_start_server()
	else:
		_start_client()


func _process(delta: float) -> void:
	_time += delta
	if is_server:
		_server_process(delta)
	else:
		_client_process(delta)
	queue_redraw()


# ---------------------------------------------------------------------------
# Entrada
# ---------------------------------------------------------------------------

func _setup_input() -> void:
	# Ambos esquemas se aceptan en cualquier cliente: cada uno controla a su personaje.
	_add_action("bs_left", [KEY_A, KEY_LEFT])
	_add_action("bs_right", [KEY_D, KEY_RIGHT])
	_add_action("bs_flap", [KEY_SPACE, KEY_ENTER, KEY_SHIFT, KEY_W, KEY_UP])
	_add_action("bs_attack", [KEY_J, KEY_K])


func _add_action(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------------------
# Arranque de red
# ---------------------------------------------------------------------------

func _start_server() -> void:
	is_server = true
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(_port, MAX_CLIENTS)
	if err != OK:
		push_error("No se pudo abrir el puerto UDP %d: %s" % [_port, error_string(err)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	phase = Phase.WAITING
	print("[SERVER] Escuchando en UDP %d. Esperando 2 jugadores..." % _port)


func _start_client() -> void:
	is_server = false
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_connect()


func _connect() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_online = false
	phase = Phase.CONNECTING
	_status = "Conectando con %s:%d..." % [_server_ip(), _port]
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_server_ip(), _port)
	if err != OK:
		phase = Phase.ERROR
		_status = "No se pudo crear el cliente (%s)" % error_string(err)
		_retry_timer = 2.0
		return
	multiplayer.multiplayer_peer = peer


func _server_ip() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ip="):
			return a.substr(5)
	return "127.0.0.1"


func _has_arg(flag: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == flag:
			return true
	return false


func _arg_int(prefix: String, fallback: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return int(a.substr(prefix.length()))
	return fallback


func _on_connected_to_server() -> void:
	_online = true
	_local_pid = multiplayer.get_unique_id()
	phase = Phase.WAITING
	_status = ""
	print("[CLIENT] Conectado como peer %d. Esperando al rival..." % _local_pid)


func _on_connection_failed() -> void:
	_online = false
	phase = Phase.ERROR
	_status = "No se pudo conectar. Reintentando..."
	_retry_timer = 2.5


func _on_server_disconnected() -> void:
	_online = false
	phase = Phase.ERROR
	_status = "Conexion perdida con el servidor."
	_retry_timer = 0.0


# ---------------------------------------------------------------------------
# Servidor: lobby y partida
# ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not is_server:
		return
	if _server_peers.has(id) or _server_peers.size() >= MAX_CLIENTS:
		return
	_server_peers.append(id)
	print("[SERVER] Jugador conectado: %d (%d/2)" % [id, _server_peers.size()])
	if _server_peers.size() >= 2 and phase == Phase.WAITING:
		_start_match()


func _on_peer_disconnected(id: int) -> void:
	if not is_server:
		return
	_server_peers.erase(id)
	print("[SERVER] Jugador desconectado: %d" % id)
	if phase == Phase.PLAYING:
		for peer_id in _server_peers:
			receive_opponent_left.rpc_id(peer_id)
		phase = Phase.WAITING
		_sim = null
		_winner = -1
	elif phase == Phase.GAME_OVER:
		phase = Phase.WAITING
		_sim = null
		_winner = -1


func _start_match() -> void:
	if _server_peers.size() < 2:
		return
	_match_seed = randi()
	_sim = MatchSim.new()
	_sim.setup(_match_seed, _server_peers)
	phase = Phase.PLAYING
	_accum = 0.0
	_winner = -1
	for peer_id in _server_peers:
		receive_match_start.rpc_id(peer_id, _match_seed, int(_server_peers[0]), int(_server_peers[1]))
	print("[SERVER] Partida iniciada. Semilla %d. Jugadores %s" % [_match_seed, str(_server_peers)])


func _server_process(delta: float) -> void:
	if _sim == null:
		return
	if phase != Phase.PLAYING and phase != Phase.GAME_OVER:
		return
	_accum += minf(delta, 0.25)
	var steps := 0
	while _accum >= TICK and steps < 6:
		_accum -= TICK
		steps += 1
		if phase == Phase.PLAYING:
			_sim.step(TICK)
			_process_sim_events()
	_broadcast_states()


func _process_sim_events() -> void:
	for ev in _sim.drain_events():
		var type := str(ev.get("type", ""))
		match type:
			"lightning":
				print("[SERVER] Rayo anti-camping sobre el jugador %d" % int(ev["pid"]))
				for peer_id in _server_peers:
					receive_lightning.rpc_id(peer_id, int(ev["pid"]), ev["pos"])
			"eliminated":
				phase = Phase.GAME_OVER
				_winner = int(ev["winner"])
				for peer_id in _server_peers:
					receive_game_over.rpc_id(peer_id, _winner)
				print("[SERVER] Ronda terminada. Ganador: %d" % _winner)


func _broadcast_states() -> void:
	for p in _sim.players:
		for peer_id in _server_peers:
			receive_player_state.rpc_id(
				peer_id, p.pid, p.pos, p.vel, p.globos, p.alive, p.facing
			)


# ---------------------------------------------------------------------------
# RPCs
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func receive_match_start(match_seed: int, p1: int, p2: int) -> void:
	if is_server:
		return
	_local_pid = multiplayer.get_unique_id()
	_peer_ids = [p1, p2]
	_local_slot = 0 if _local_pid == p1 else 1
	_match_seed = match_seed
	var map := MapGen.generate(match_seed)
	_platforms = map["platforms"]
	_spawns = map["spawns"]
	_clouds = map["clouds"]
	_states.clear()
	_fx.clear()
	_winner = -1
	_over_reason = ""
	phase = Phase.PLAYING
	print("[CLIENT] Partida iniciada (slot %d, semilla %d)" % [_local_slot, match_seed])


@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_state(
	pid: int, pos: Vector2, vel: Vector2, globos: int, alive: bool, facing: int
) -> void:
	if is_server:
		return
	if phase != Phase.PLAYING and phase != Phase.GAME_OVER:
		return

	var snap := {
		"pos": pos,
		"vel": vel,
		"globos": globos,
		"alive": alive,
		"facing": facing,
	}
	if not _states.has(pid):
		_states[pid] = {"prev": snap, "next": snap, "t": 1.0, "flash": 0.0}
		return

	var st: Dictionary = _states[pid]
	var old_next: Dictionary = st["next"]
	var snapped := false
	if old_next["pos"].distance_to(pos) > 60.0:
		snapped = true
	if int(old_next["globos"]) > globos:
		st["flash"] = 0.3
	st["prev"] = snap if snapped else old_next
	st["next"] = snap
	st["t"] = 1.0 if snapped else 0.0


@rpc("authority", "call_remote", "reliable")
func receive_game_over(winner: int) -> void:
	if is_server:
		return
	_winner = winner
	_over_reason = "globos"
	phase = Phase.GAME_OVER
	print("[CLIENT] Fin de partida. Ganador: %d" % winner)
	if _has_arg("--quit-on-gameover"):
		get_tree().quit()


@rpc("authority", "call_remote", "reliable")
func receive_opponent_left() -> void:
	if is_server:
		return
	_winner = _local_pid
	_over_reason = "opponent_left"
	phase = Phase.GAME_OVER


@rpc("authority", "call_remote", "reliable")
func receive_lightning(pid: int, pos: Vector2) -> void:
	if is_server:
		return
	_fx.append({"pos": pos, "t": 0.0, "life": 0.55, "pid": pid})
	print("[CLIENT] Rayo sobre el jugador %d" % pid)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func receive_input(mx: float, flap: bool, attack: bool) -> void:
	if not is_server or _sim == null or phase != Phase.PLAYING:
		return
	var sender := multiplayer.get_remote_sender_id()
	_sim.set_input(sender, mx, flap, attack)


# ---------------------------------------------------------------------------
# Cliente: proceso
# ---------------------------------------------------------------------------

func _client_process(delta: float) -> void:
	if phase == Phase.ERROR and _retry_timer > 0.0:
		_retry_timer -= delta
		if _retry_timer <= 0.0:
			_connect()

	for pid in _states.keys():
		var st: Dictionary = _states[pid]
		st["t"] = minf(1.0, float(st["t"]) + delta / INTERP_TIME)
		st["flash"] = maxf(0.0, float(st["flash"]) - delta)

	var fx_alive: Array = []
	for fx in _fx:
		fx["t"] = float(fx["t"]) + delta
		if float(fx["t"]) < float(fx["life"]):
			fx_alive.append(fx)
	_fx = fx_alive

	if phase == Phase.PLAYING and _online:
		var mx := 0.0
		if Input.is_action_pressed("bs_left"):
			mx -= 1.0
		if Input.is_action_pressed("bs_right"):
			mx += 1.0
		var flap := Input.is_action_pressed("bs_flap")
		var attack := Input.is_action_pressed("bs_attack")
		_local_input["mx"] = mx
		_local_input["flap"] = flap
		_local_input["attack"] = attack
		receive_input.rpc_id(1, mx, flap, attack)

	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()


# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------

func _draw() -> void:
	if is_server:
		return

	_draw_sky()

	if phase == Phase.CONNECTING or phase == Phase.ERROR:
		_draw_connect_screen()
		return
	if phase == Phase.WAITING:
		_draw_waiting_screen()
		return

	_draw_world()
	_draw_hud()
	if phase == Phase.GAME_OVER:
		_draw_game_over()


func _draw_sky() -> void:
	draw_rect(Rect2(0, 0, 320, 180), COL_SKY_TOP)
	draw_rect(Rect2(0, 38, 320, 64), COL_SKY_MID)
	draw_rect(Rect2(0, 102, 320, 78), COL_SKY_LOW)
	for s in _stars:
		var tw := 0.35 + 0.45 * absf(sin(_time * 1.6 + s.x * 0.7 + s.y * 0.3))
		draw_rect(Rect2(s.x, s.y, 1, 1), Color(COL_STAR.r, COL_STAR.g, COL_STAR.b, tw))


func _draw_world() -> void:
	for c in _clouds:
		draw_rect(Rect2(c.position, c.size), COL_CLOUD)
		draw_rect(Rect2(c.position.x + 3.0, c.position.y - 1.0, maxf(1.0, c.size.x - 6.0), 1), COL_CLOUD)

	_draw_water()

	for r in _platforms:
		var rr := Rect2(r.position.round(), r.size)
		draw_rect(rr, COL_OUTLINE)
		draw_rect(Rect2(rr.position + Vector2(0, 1), Vector2(rr.size.x, rr.size.y - 2)), COL_PLATFORM)
		draw_rect(Rect2(rr.position + Vector2(0, 1), Vector2(rr.size.x, 2)), COL_PLATFORM_TOP)
		draw_rect(
			Rect2(rr.position.x, rr.position.y + rr.size.y - 3, rr.size.x, 2), COL_PLATFORM_DARK
		)

	_draw_players()
	_draw_fx()


func _draw_water() -> void:
	var depth := 180.0 - MapGen.WATER_Y
	draw_rect(Rect2(0, MapGen.WATER_Y, 320, depth), COL_WATER)
	draw_rect(Rect2(0, 178, 320, 2), COL_WATER_DARK)
	var x := 0.0
	while x < 320.0:
		var wave: float = round(MapGen.WATER_Y + sin(_time * 2.2 + x * 0.12) * 1.1)
		draw_rect(Rect2(x, wave, 7, 1), COL_WATER_LINE)
		draw_rect(Rect2(x + 3.0, wave + 2.0, 5, 1), Color(COL_WATER, 0.55))
		x += 9.0


func _draw_players() -> void:
	for pid in _states.keys():
		var v := _visual(int(pid))
		if not bool(v["alive"]):
			continue
		var slot := int(v["slot"])
		var color := COL_P1 if slot == 0 else COL_P2
		var light := COL_P1_LIGHT if slot == 0 else COL_P2_LIGHT
		var vel: Vector2 = v["vel"]
		_draw_character(
			v["pos"], color, light, int(v["globos"]), int(v["facing"]), vel.y, float(v["flash"])
		)
		if int(pid) == _local_pid:
			_draw_local_marker(v["pos"])


func _visual(pid: int) -> Dictionary:
	var st: Dictionary = _states[pid]
	var prev: Dictionary = st["prev"]
	var next: Dictionary = st["next"]
	var t := clampf(float(st["t"]), 0.0, 1.0)
	var p0: Vector2 = prev["pos"]
	var p1: Vector2 = next["pos"]
	return {
		"pos": p0.lerp(p1, t),
		"vel": next["vel"],
		"globos": int(next["globos"]),
		"alive": bool(next["alive"]),
		"facing": int(next["facing"]),
		"flash": float(st["flash"]),
		"slot": _slot_of(pid),
	}


func _slot_of(pid: int) -> int:
	if _peer_ids.size() >= 2 and pid == int(_peer_ids[1]):
		return 1
	return 0


func _draw_character(
	pos: Vector2,
	color: Color,
	light: Color,
	globos: int,
	facing: int,
	vel_y: float,
	flash: float
) -> void:
	var base := pos.round()

	# Globos atados a la espalda (detrás del cuerpo).
	for i in range(2):
		if i >= globos:
			continue
		var off := MatchSim.balloon_offset(i)
		var bob := sin(_time * 3.1 + i * 1.9) * 1.2
		var bc := (base + off + Vector2(0, bob)).round()
		var knot := base + Vector2(-2.0 + float(i) * 4.0, -3.0)
		draw_line(Vector2(bc.x, bc.y + 5.0), knot, Color("#22304d"), 1.0)
		_draw_balloon(bc, color, light)

	# Cuerpo.
	draw_rect(Rect2(base.x - 5.0, base.y - 6.0, 10.0, 12.0), COL_OUTLINE)
	draw_rect(Rect2(base.x - 4.0, base.y - 5.0, 8.0, 10.0), color)
	draw_rect(Rect2(base.x - 4.0, base.y - 5.0, 8.0, 2.0), light)
	# Visor.
	var visor_x := base.x + 1.0 if facing > 0 else base.x - 4.0
	draw_rect(Rect2(visor_x, base.y - 3.0, 3.0, 2.0), Color("#101a30"))
	# Brazos (arriba al aletear).
	var arm_y := base.y - 5.0 if vel_y < -40.0 else base.y + 1.0
	draw_rect(Rect2(base.x - 6.0, arm_y, 2.0, 2.0), light)
	draw_rect(Rect2(base.x + 4.0, arm_y, 2.0, 2.0), light)
	# Piernas.
	draw_rect(Rect2(base.x - 3.0, base.y + 5.0, 2.0, 2.0), COL_OUTLINE)
	draw_rect(Rect2(base.x + 1.0, base.y + 5.0, 2.0, 2.0), COL_OUTLINE)

	if flash > 0.0:
		draw_rect(
			Rect2(base.x - 5.0, base.y - 6.0, 10.0, 12.0),
			Color(1.0, 1.0, 1.0, clampf(flash * 2.0, 0.0, 0.8))
		)


func _draw_balloon(bc: Vector2, color: Color, light: Color) -> void:
	draw_rect(Rect2(bc.x - 4.0, bc.y - 5.0, 8.0, 10.0), COL_OUTLINE)
	draw_rect(Rect2(bc.x - 3.0, bc.y - 4.0, 6.0, 8.0), color)
	draw_rect(Rect2(bc.x - 2.0, bc.y - 4.0, 2.0, 1.0), light)
	draw_rect(Rect2(bc.x + 1.0, bc.y - 3.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.5))
	draw_rect(Rect2(bc.x - 1.0, bc.y + 4.0, 2.0, 1.0), light)


func _draw_local_marker(pos: Vector2) -> void:
	var bob := sin(_time * 4.0) * 1.5
	var y := pos.y - 27.0 + bob
	var pts := PackedVector2Array([
		Vector2(pos.x - 2.0, y - 3.0),
		Vector2(pos.x + 2.0, y - 3.0),
		Vector2(pos.x, y),
	])
	draw_colored_polygon(pts, COL_TEXT)


func _draw_fx() -> void:
	for fx in _fx:
		var pos: Vector2 = fx["pos"]
		var t := float(fx["t"]) / float(fx["life"])
		if t < 0.45:
			var top := Vector2(pos.x + sin(pos.y * 0.7) * 6.0, 2.0)
			var pts: Array[Vector2] = [
				top,
				Vector2((top.x + pos.x) * 0.5 - 4.0, 48.0),
				Vector2((top.x + pos.x) * 0.5 + 3.0, 82.0),
				Vector2(pos.x - 2.0, 118.0),
				pos,
			]
			for i in range(pts.size() - 1):
				draw_line(pts[i], pts[i + 1], COL_BOLT, 1.0)
			draw_line(pts[0] + Vector2(1, 0), pts[1] + Vector2(1, 0), Color(1, 1, 1, 0.4), 1.0)
		var r := 7.0 * (1.0 - t)
		if r > 0.5:
			draw_rect(
				Rect2(pos.x - r, pos.y - r, r * 2.0, r * 2.0),
				Color(1.0, 0.94, 0.55, clampf(1.0 - t * 1.8, 0.0, 1.0))
			)


# ---------------------------------------------------------------------------
# HUD y pantallas
# ---------------------------------------------------------------------------

func _draw_hud() -> void:
	if _peer_ids.size() < 2:
		return
	var my_pid := int(_peer_ids[_local_slot])
	var rival_pid := int(_peer_ids[1 - _local_slot])
	var my_globos := 2
	var rival_globos := 2
	if _states.has(my_pid):
		my_globos = int(_visual(my_pid)["globos"])
	if _states.has(rival_pid):
		rival_globos = int(_visual(rival_pid)["globos"])

	var my_color := COL_P1 if _local_slot == 0 else COL_P2
	var rival_color := COL_P1 if _local_slot == 1 else COL_P2

	draw_rect(Rect2(3, 3, 40, 14), Color(0.0, 0.0, 0.0, 0.28))
	_text_left("TU", 6, 13, 6, COL_TEXT_DIM)
	_draw_pips(20, 6, my_globos, my_color)

	draw_rect(Rect2(277, 3, 40, 14), Color(0.0, 0.0, 0.0, 0.28))
	_text_right("RIVAL", 314, 13, 6, COL_TEXT_DIM)
	_draw_pips(279, 6, rival_globos, rival_color)


func _draw_pips(x: float, y: float, globos: int, color: Color) -> void:
	for i in range(2):
		var px := x + float(i) * 7.0
		draw_rect(Rect2(px, y, 5, 7), COL_OUTLINE)
		var c := color if i < globos else Color(1.0, 1.0, 1.0, 0.12)
		draw_rect(Rect2(px + 1.0, y + 1.0, 3, 5), c)
		draw_rect(Rect2(px + 2.0, y + 7.0, 1, 1), COL_OUTLINE)


func _draw_waiting_screen() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(0.02, 0.03, 0.09, 0.35))
	_text_center("BALLOON SMASH", 50, 22, COL_TEXT)
	_text_center("ARENA PIXEL ONLINE", 62, 7, COL_TEXT_DIM)

	_draw_character(Vector2(118, 108), COL_P1, COL_P1_LIGHT, 2, 1, 0.0, 0.0)
	_draw_character(Vector2(202, 108), COL_P2, COL_P2_LIGHT, 2, -1, 0.0, 0.0)

	var dots := ""
	for i in range(int(_time * 2.0) % 4):
		dots += "."
	_text_center("Esperando jugador" + dots, 142, 11, COL_TEXT)
	_text_center("La partida empieza en cuanto entre el segundo jugador.", 154, 6, COL_TEXT_DIM)
	_text_center(
		"WASD / Flechas: mover    Espacio / Enter: aletear    J / K: atacar", 172, 6, COL_TEXT_DIM
	)


func _draw_connect_screen() -> void:
	_text_center("BALLOON SMASH", 56, 22, COL_TEXT)
	var msg := _status
	if msg == "":
		msg = "Conectando..."
	var col := COL_P1_LIGHT if phase == Phase.ERROR else COL_TEXT
	_text_center(msg, 100, 8, col)
	_text_center("Servidor: %s:%d" % [_server_ip(), _port], 114, 7, COL_TEXT_DIM)
	_text_center("Arranca el servidor con:", 140, 6, COL_TEXT_DIM)
	_text_center("godot --headless --path . -- --server", 150, 6, COL_TEXT)
	_text_center("ESC para salir", 172, 6, COL_TEXT_DIM)


func _draw_game_over() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(0.015, 0.02, 0.06, 0.62))
	if _over_reason == "opponent_left":
		_text_center("EL RIVAL SE DESCONECTO", 82, 13, COL_TEXT)
		_text_center("Partida terminada", 100, 7, COL_TEXT_DIM)
	else:
		var won := _winner == _local_pid
		var title := "VICTORIA!" if won else "DERROTA"
		var col := COL_BOLT if won else COL_P1_LIGHT
		_text_center(title, 84, 22, col)
		if won:
			_text_center("Reventaste los 2 globos del rival.", 104, 7, COL_TEXT_DIM)
		else:
			_text_center("Te quedaste sin globos.", 104, 7, COL_TEXT_DIM)
	_text_center("ESC para salir", 156, 6, COL_TEXT_DIM)


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

func _build_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	_stars.clear()
	for i in range(46):
		_stars.append(Vector2(float(rng.randi_range(0, 319)), float(rng.randi_range(4, 128))))


func _text_center(text: String, y: float, size: int, color: Color) -> void:
	draw_string(
		ThemeDB.fallback_font,
		Vector2(0, y),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		320.0,
		size,
		color
	)


func _text_left(text: String, x: float, y: float, size: int, color: Color) -> void:
	draw_string(
		ThemeDB.fallback_font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color
	)


func _text_right(text: String, x_right: float, y: float, size: int, color: Color) -> void:
	draw_string(
		ThemeDB.fallback_font,
		Vector2(x_right - 120.0, y),
		text,
		HORIZONTAL_ALIGNMENT_RIGHT,
		120.0,
		size,
		color
	)

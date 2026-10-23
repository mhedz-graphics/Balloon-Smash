extends SceneTree

## Pruebas automáticas del MVP (sin red). Ejecutar:
##   godot --headless --path . -s res://tests/sim_test.gd

var _fails := 0
var _total := 0


func _initialize() -> void:
	_test_map_determinism()
	_test_flight_and_platforms()
	_test_water()
	_test_stomp_and_victory()
	_test_melee()
	_test_lightning()

	print("\n%d/%d pruebas OK" % [_total - _fails, _total])
	quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("  ok   ", label)
	else:
		_fails += 1
		print("  FAIL ", label)


func _test_map_determinism() -> void:
	print("[mapa]")
	var a := MapGen.generate(123456)
	var b := MapGen.generate(123456)
	var pa: Array[Rect2] = a["platforms"]
	var pb: Array[Rect2] = b["platforms"]
	_check(pa == pb, "misma semilla => mismas plataformas")
	_check(pa.size() >= 6, "hay plataformas suficientes (%d)" % pa.size())

	var spawns: Array[Vector2] = a["spawns"]
	for s in spawns:
		var near := 0
		for r in pa:
			if absf(r.get_center().x - s.x) < 96.0 and absf(r.get_center().y - s.y) < 78.0:
				near += 1
		_check(near >= 2, "spawn %s tiene 2+ plataformas cerca (%d)" % [str(s), near])
		var blocked := false
		for r in pa:
			if Rect2(s.x - 10.0, s.y - 10.0, 20.0, 20.0).intersects(r):
				blocked = true
		_check(not blocked, "zona de spawn despejada")


func _test_flight_and_platforms() -> void:
	print("[vuelo]")
	var sim := MatchSim.new()
	sim.setup(999, [10, 20])
	var p := sim.get_player(10)

	for i in range(120):
		sim.step(1.0 / 60.0)
	_check(p.on_ground, "el personaje aterriza en la plataforma de spawn")

	var y_before := p.pos.y
	sim.set_input(10, 0.0, true, false)
	sim.step(1.0 / 60.0)
	_check(p.vel.y < 0.0, "el aleteo impulsa hacia arriba")
	for i in range(8):
		sim.step(1.0 / 60.0)
	_check(p.pos.y < y_before, "el personaje gana altura")

	sim.set_input(10, 1.0, false, false)
	for i in range(30):
		sim.step(1.0 / 60.0)
	_check(p.vel.x > 10.0, "hay desplazamiento horizontal")
	sim.set_input(10, 0.0, false, false)
	sim.step(1.0 / 60.0)
	_check(absf(p.vel.x) > 10.0, "la inercia se conserva (no frena de golpe)")

	var low := MatchSim.new()
	low.setup(44, [1, 2])
	var q := low.get_player(1)
	q.globos = 1
	q.balloons = [true, false]
	q.pos = Vector2(64, 60)
	q.vel = Vector2.ZERO
	low.step(1.0 / 60.0)
	_check(q.vel.y > MatchSim.GRAVITY_NORMAL / 60.0, "con 1 globo cae más rápido")


func _test_water() -> void:
	print("[agua]")
	var sim := MatchSim.new()
	sim.setup(555, [7, 8])
	var p := sim.get_player(7)
	p.pos = Vector2(30, 170)
	p.vel = Vector2.ZERO
	sim.step(1.0 / 60.0)
	_check(p.globos == 1, "caer al agua quita 1 globo")
	_check(p.pos == sim.spawns[0], "tras el agua reaparece en el spawn")
	_check(p.alive, "sigue vivo con 1 globo")
	var types := []
	for ev in sim.drain_events():
		types.append(str(ev.get("type", "")))
	_check(types.has("splash"), "emite evento de splash")

	p.pos = Vector2(30, 170)
	sim.step(1.0 / 60.0)
	_check(p.globos == 0 and not p.alive, "segunda caída => eliminado")
	_check(sim.over and sim.winner_pid == 8, "el rival gana la partida")


func _test_stomp_and_victory() -> void:
	print("[pisotón]")
	var sim := MatchSim.new()
	sim.setup(777, [11, 22])
	var a := sim.get_player(11)
	var b := sim.get_player(22)
	sim.platforms.clear()
	b.pos = Vector2(160, 100)
	b.vel = Vector2.ZERO

	a.pos = b.pos + Vector2(0, -24)
	a.vel = Vector2(0, 200)
	a.melee_cd = 0.0
	sim.set_input(11, 0.0, false, true)
	sim.step(1.0 / 60.0)
	_check(b.globos == 1, "el pisotón revienta 1 globo")
	_check(a.vel.y < 0.0, "el pisotón rebota al atacante")
	_check(not sim.over, "la partida sigue con 1 globo")

	sim.set_input(11, 0.0, false, false)
	b.pos = Vector2(160, 100)
	b.vel = Vector2.ZERO
	a.pos = b.pos + Vector2(0, -24)
	a.vel = Vector2(0, 200)
	a.melee_cd = 0.0
	sim.set_input(11, 0.0, false, true)
	sim.step(1.0 / 60.0)
	_check(b.globos == 0 and not b.alive, "el segundo pisotón elimina al rival")
	_check(sim.over and sim.winner_pid == 11, "victoria al reventar los 2 globos")


func _test_melee() -> void:
	print("[cuerpo a cuerpo]")
	var sim := MatchSim.new()
	sim.setup(31337, [31, 41])
	var a := sim.get_player(31)
	var b := sim.get_player(41)
	sim.platforms.clear()
	a.pos = Vector2(150, 100)
	b.pos = Vector2(168, 100)
	a.vel = Vector2.ZERO
	b.vel = Vector2.ZERO
	a.facing = 1
	sim.set_input(31, 0.0, false, true)
	sim.step(1.0 / 60.0)
	_check(b.globos == 2, "el golpe cuerpo a cuerpo no revienta globos")
	_check(b.vel.x > 100.0, "el golpe aplica knockback horizontal")


func _test_lightning() -> void:
	print("[rayo]")
	var sim := MatchSim.new()
	sim.setup(2024, [51, 61])
	sim.since_damage = MatchSim.LIGHTNING_INTERVAL - 0.05
	sim.step(0.1)
	var globos_total := 0
	for p in sim.players:
		globos_total += p.globos
	_check(globos_total == 3, "el rayo quita exactamente 1 globo")
	var types := []
	for ev in sim.drain_events():
		types.append(str(ev.get("type", "")))
	_check(types.has("lightning"), "emite evento de rayo")

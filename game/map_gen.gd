class_name MapGen
extends RefCounted

## Generación procedural de la arena.
## Es determinista: con la misma semilla, servidor y clientes obtienen el mismo mapa.

const WORLD := Vector2(320.0, 180.0)
const WATER_Y := 165.0

static func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var spawns: Array[Vector2] = [Vector2(64.0, 96.0), Vector2(256.0, 96.0)]
	var platforms: Array[Rect2] = []

	# Plataforma de aterrizaje garantizada bajo cada spawn.
	for s in spawns:
		var hx := clampf(s.x - 26.0, 12.0, WORLD.x - 12.0 - 52.0)
		var hy := clampf(s.y + 26.0, 50.0, WATER_Y - 20.0)
		platforms.append(Rect2(hx, hy, 52.0, 8.0))

	# Plataformas flotantes aleatorias con separación mínima y spawns despejados.
	var target_count := 8
	var tries := 0
	while platforms.size() < target_count and tries < 240:
		tries += 1
		var w := float(rng.randi_range(34, 70))
		var h := 8.0
		var x := float(rng.randi_range(12, int(WORLD.x) - 12 - int(w)))
		var y := float(rng.randi_range(46, int(WATER_Y) - 26 - int(h)))
		var candidate := Rect2(x, y, w, h)
		if _overlaps_any(candidate, platforms, 14.0):
			continue
		if _blocks_spawn(candidate, spawns):
			continue
		platforms.append(candidate)

	# Garantiza al menos 2 plataformas cerca de cada spawn (la de aterrizaje + extra).
	for s in spawns:
		var near := 0
		for r in platforms:
			if absf(r.get_center().x - s.x) < 96.0 and absf(r.get_center().y - s.y) < 78.0:
				near += 1
		var guard := 0
		while near < 2 and guard < 48:
			guard += 1
			var w2 := float(rng.randi_range(36, 58))
			var x2 := clampf(s.x + rng.randf_range(-48.0, 28.0), 12.0, WORLD.x - 12.0 - w2)
			var y2 := clampf(s.y + rng.randf_range(-20.0, 42.0), 46.0, WATER_Y - 26.0)
			var candidate2 := Rect2(x2, y2, w2, 8.0)
			if _overlaps_any(candidate2, platforms, 12.0):
				continue
			if _blocks_spawn(candidate2, spawns):
				continue
			platforms.append(candidate2)
			near += 1

	# Nubes decorativas (no colisionan).
	var clouds: Array[Rect2] = []
	var cloud_rng := RandomNumberGenerator.new()
	cloud_rng.seed = seed_value * 7919 + 13
	for i in range(6):
		var cw := float(cloud_rng.randi_range(14, 38))
		var cx := float(cloud_rng.randi_range(0, int(WORLD.x) - int(cw)))
		var cy := float(cloud_rng.randi_range(12, 118))
		clouds.append(Rect2(cx, cy, cw, 3.0))

	return {
		"platforms": platforms,
		"spawns": spawns,
		"clouds": clouds,
	}

static func _overlaps_any(r: Rect2, list: Array[Rect2], gap: float) -> bool:
	var grown := r.grow(gap)
	for o in list:
		if grown.intersects(o):
			return true
	return false

static func _blocks_spawn(r: Rect2, spawns: Array[Vector2]) -> bool:
	for s in spawns:
		var zone := Rect2(s.x - 20.0, s.y - 26.0, 40.0, 44.0)
		if zone.intersects(r):
			return true
	return false

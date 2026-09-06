extends RefCounted
## Authored district expansion. Shared physics/navigation, economy and save identifiers.
const REGION_IDS := ["parque", "shopping", "cinema"]
const STAIRS := [
	[Vector3(36, 4, -4), Vector3(36, 0, 10), 4.8],
	[Vector3(33, 0, 58), Vector3(33, 4.2, 37), 4.8],
	[Vector3(60, 4.2, 67), Vector3(40, 0, 67), 4.8],
	[Vector3(43, 0, -2), Vector3(43, 0.9, -7.5), 3.4]
]
const LANDMARKS := {
	"jardim": Vector3(0, 0.2, 44), "estufa": Vector3(-8, 0.2, 61),
	"quiosque": Vector3(13, 0.2, 64), "atrio": Vector3(46, 0.2, 49),
	"farmacia": Vector3(32, 0.2, 30), "arsenal": Vector3(66, 0.2, 43),
	"cafe": Vector3(31, 0.2, 65), "oficina_loja": Vector3(66, 0.2, 57),
	"mezanino": Vector3(50, 4.4, 32), "terraco": Vector3(67, 4.4, 68),
	"bilheteria": Vector3(39, 0.2, 19), "plateia": Vector3(57, 0.2, 6),
	"palco": Vector3(57, 1.1, -10), "projecao": Vector3(35, 0.2, -10)
}
const GREEN := Color("395d43")
const LEAF := Color("587955")
const TILE := Color("798581")
const RED := Color("653d49")
var w: Node3D

static func register(world: Node3D) -> void:
	world.regions.append_array([
		{"id":"parque", "name":"Jardim das Nascentes", "center":Vector3(0, 0, 44), "unlock_cost":120, "unlock_round":1},
		{"id":"shopping", "name":"Shopping Aurora", "center":Vector3(46, 0, 49), "unlock_cost":320, "unlock_round":2},
		{"id":"cinema", "name":"Cine Última Luz", "center":Vector3(57, 0, 6), "unlock_cost":480, "unlock_round":3}
	])
	world.spawn_points.append_array([
		Vector3(-9, 0.25, 40), Vector3(15, 0.25, 39), Vector3(0, 0.25, 68), Vector3(16, 0.25, 58),
		Vector3(47, 0.25, 39), Vector3(55, 0.25, 59), Vector3(50, 4.45, 32), Vector3(68, 4.45, 60),
		Vector3(39, 0.25, 19), Vector3(57, 0.25, -5), Vector3(68, 0.25, 10), Vector3(35, 0.25, -10)
	])
	world.shops.append_array([
		{"id":"quiosque_nascente", "name":"Cantinho de Faro", "position":Vector3(13, 0.2, 64), "type":"merchant"},
		{"id":"arsenal_aurora", "name":"Arsenal Aurora", "position":Vector3(66, 0.2, 43), "type":"merchant"},
		{"id":"forja_aurora", "name":"Oficina de Precisão", "position":Vector3(66, 0.2, 57), "type":"forge"}
	])
	world.points_of_interest.append_array([
		{"id":"porta_parque_patio", "type":"door", "name":"Jardim das Nascentes", "position":Vector3(0, 0.2, 28), "cost":120, "region_id":"parque"},
		{"id":"porta_parque_shopping", "type":"door", "name":"Jardim das Nascentes", "position":Vector3(21, 0.2, 52), "cost":120, "region_id":"parque"},
		{"id":"porta_shopping_parque", "type":"door", "name":"Shopping Aurora", "position":Vector3(27, 0.2, 52), "cost":320, "region_id":"shopping"},
		{"id":"porta_shopping_cinema", "type":"door", "name":"Shopping Aurora", "position":Vector3(53, 0.2, 28), "cost":320, "region_id":"shopping"},
		{"id":"porta_cinema_shopping", "type":"door", "name":"Cine Última Luz", "position":Vector3(53, 0.2, 21), "cost":480, "region_id":"cinema"},
		{"id":"porta_cinema_oficina", "type":"door", "name":"Cine Última Luz", "position":Vector3(32, 4.2, -7), "cost":480, "region_id":"cinema"},
		{"id":"porta_oficina_cinema", "type":"door", "name":"Oficina Suspensa", "position":Vector3(27, 4.2, -7), "cost":180, "region_id":"oficina"},
		{"id":"quiosque_parque", "type":"merchant", "name":"Cantinho de Faro", "position":Vector3(13, 0.2, 64), "cost":0, "region_id":"parque"},
		{"id":"bau_estufa", "type":"chest", "name":"Reserva da estufa", "position":Vector3(-8, 0.2, 61), "cost":60, "region_id":"parque"},
		{"id":"desafio_nascente", "type":"challenge", "name":"Defender a nascente", "position":Vector3(15, 0.2, 39), "cost":0, "region_id":"parque", "target":10, "duration":80},
		{"id":"arsenal_shopping", "type":"merchant", "name":"Arsenal Aurora", "position":Vector3(66, 0.2, 43), "cost":0, "region_id":"shopping"},
		{"id":"forja_shopping", "type":"forge", "name":"Oficina de Precisão", "position":Vector3(66, 0.2, 57), "cost":0, "region_id":"shopping"},
		{"id":"bau_farmacia", "type":"chest", "name":"Estoque da farmácia", "position":Vector3(32, 0.2, 30), "cost":100, "region_id":"shopping"},
		{"id":"reserva_cafe", "type":"cache", "name":"Entrega no café", "position":Vector3(31, 0.2, 65), "cost":0, "region_id":"shopping"},
		{"id":"cofre_mezanino", "type":"chest", "name":"Cofre do mezanino", "position":Vector3(68, 4.4, 62), "cost":200, "region_id":"shopping"},
		{"id":"reserva_projecao", "type":"cache", "name":"Arquivo do projecionista", "position":Vector3(35, 0.2, -10), "cost":0, "region_id":"cinema"},
		{"id":"desafio_cinema", "type":"challenge", "name":"Última sessão", "position":Vector3(57, 1.1, -10), "cost":0, "region_id":"cinema", "target":16, "duration":90},
		{"id":"bau_bilheteria", "type":"chest", "name":"Caixa da bilheteria", "position":Vector3(39, 0.2, 19), "cost":150, "region_id":"cinema"}
	])

static func gates(world: Node3D) -> void:
	world._gate("parque", Vector3(0, 0, 29), 6, false, "porta_parque_patio")
	world._gate("parque", Vector3(22, 0, 52), 8, true, "porta_parque_shopping")
	world._gate("shopping", Vector3(26, 0, 52), 8, true, "porta_shopping_parque")
	world._gate("shopping", Vector3(53, 0, 27), 6, false, "porta_shopping_cinema")
	world._gate("cinema", Vector3(53, 0, 22), 6, false, "porta_cinema_shopping")
	world._gate("cinema", Vector3(31, 4, -7), 6, true, "porta_cinema_oficina")
	world._gate("oficina", Vector3(28, 4, -7), 6, true, "porta_oficina_cinema")

func build(world: Node3D) -> void:
	w = world
	w._box("ExpandedHillside", Vector3(20, -11, 22), Vector3(120, 10, 158), Color("23373c"))
	_park()
	_mall()
	_cinema()
	for index in range(STAIRS.size()):
		var route: Array = STAIRS[index]
		w._ramp("ExpansionStair%d" % index, route[0], route[1], route[2])
	# Two independently gated ends preserve region costs in either travel direction.
	w._floor("CinemaServiceBridge", Vector3(31.5, 4, -7), Vector2(7, 6))
	w._floor("CinemaUpperLanding", Vector3(36, 4, -7), Vector2(4.8, 6))
	w._edge(Vector3(28, 4, -10), Vector3(38.4, 4, -10), 1.4)
	w._edge(Vector3(28, 4, -4), Vector3(33.5, 4, -4), 1.4)
	w._edge(Vector3(38.4, 4, -10), Vector3(38.4, 4, -4), 1.4)
	w._sign("CINEMA  →", Vector3(26.5, 6.2, -10.1), 3.1)

func _park() -> void:
	w._floor("GardenEntrance", Vector3(0, 0, 28.5), Vector2(6, 7))
	for x: float in [-3, 3]: w._edge(Vector3(x, 0, 25), Vector3(x, 0, 32), 2)
	w._floor("Garden", Vector3(5, 0, 52), Vector2(38, 40))
	w._box("GardenLawn", Vector3(5, 0.022, 52), Vector3(37.8, 0.035, 39.8), GREEN)
	# Cross and perimeter paths read clearly and offer a loop around planted cover.
	for rect: Array in [[5, 36, 37, 6], [5, 69, 37, 6], [-10, 52, 6, 34], [19, 52, 6, 34], [4, 52, 34, 6], [0, 44, 6, 18]]:
		w._box("GardenFootpath", Vector3(rect[0], 0.052, rect[1]), Vector3(rect[2], 0.045, rect[3]), TILE.darkened(0.15))
	w._edge(Vector3(-14, 0, 32), Vector3(-3, 0, 32), 2)
	w._edge(Vector3(3, 0, 32), Vector3(24, 0, 32), 2)
	for ends: Vector2 in [Vector2(32,49.5),Vector2(54.5,63.5),Vector2(68.5,72)]:
		w._edge(Vector3(-14,0,ends.x),Vector3(-14,0,ends.y),2)
	w._edge(Vector3(-14, 0, 72), Vector3(24, 0, 72), 2)
	w._edge(Vector3(24, 0, 32), Vector3(24, 0, 48), 2)
	w._edge(Vector3(24, 0, 56), Vector3(24, 0, 72), 2)
	# Constrain both approach gates; the corridor itself stays fully navigable.
	for z: float in [48, 56]: w._edge(Vector3(20, 0, z), Vector3(28, 0, z), 2.2)
	for p: Vector3 in [Vector3(-6, 0, 42), Vector3(9, 0, 43), Vector3(14, 0, 45), Vector3(6, 0, 61), Vector3(-11, 0, 67), Vector3(20, 0, 34)]:
		_tree(p)
	w._cylinder("SpringStoneRim", Vector3(6, 0.32, 55.5), 2.4, 0.64, w.STONE, true)
	w._cylinder("SpringWater", Vector3(6, 0.65, 55.5), 2.0, 0.03, Color("417f83"), false, 0.15)
	w._cylinder("SpringColumn", Vector3(6, 1.1, 55.5), 0.45, 1.3, w.PLASTER, true)
	for p: Vector3 in [Vector3(-6, 0, 48), Vector3(12, 0, 56), Vector3(3, 0, 69)]: w._bench(p)
	# A real greenhouse room, with open front and side doors and planted benches.
	_greenhouse()
	w._sign("ESTUFA • RESERVA", Vector3(-8, 3.2, 65.2), 6)
	w._sign("ESTUFA", Vector3(-12.7, 3.2, 61), 3.5, -PI / 2)
	for x: float in [-11, -5]:
		w._box("GrowingBed", Vector3(x, 0.45, 59.5), Vector3(1.2, 0.9, 3.6), w.RUST, true)
		for z: float in [58.5, 59.5, 60.5]: _bush(Vector3(x, 1.2, z), 0.55)
	w._stall(Vector3(13, 0, 65.5))
	w._sign("CANTINHO DE FARO", Vector3(13, 3, 64.5), 5, PI)
	w._sign("JARDIM DAS NASCENTES", Vector3(0, 3.5, 32.1), 6, PI)
	w._sign("SHOPPING  →", Vector3(18.5, 2.8, 47.8), 4)
	for p: Vector3 in [Vector3(-10, 3.8, 37), Vector3(16, 3.8, 54), Vector3(-8, 3.3, 62), Vector3(13, 3.5, 65)]:
		w._lamp(p, Color("c9cf96"), 13)
		if p.z < 56: w._cylinder("GardenLightPost", p - Vector3(0, p.y / 2, 0), 0.075, p.y, w.DARK)
	# One deterministic multimesh for grass, hidden by the vegetation setting.
	var grass := MultiMeshInstance3D.new()
	grass.name = "GardenGrass"
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	var blade := PrismMesh.new()
	blade.size = Vector3(0.12, 0.42, 0.12)
	multi.mesh = blade
	multi.instance_count = 160
	var rng := RandomNumberGenerator.new()
	rng.seed = 85922
	for index in range(160):
		var center := Vector3(-6, 0.23, 42) if index < 80 else Vector3(9, 0.23, 61)
		var at := center + Vector3(rng.randf_range(-2.1, 2.1), 0, rng.randf_range(-2, 2))
		multi.set_instance_transform(index, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at))
	grass.multimesh = multi
	grass.material_override = w._material(LEAF)
	w._geometry.add_child(grass)
	w._vegetation.append(grass)

func _mall() -> void:
	w._floor("MallGround", Vector3(48, 0, 49), Vector2(48, 50))
	w._box("MallTiles", Vector3(48, 0.024, 49), Vector3(47.8, 0.04, 49.8), TILE)
	for x in range(28, 73, 4): w._box("TileJoint", Vector3(x, 0.05, 49), Vector3(0.025, 0.02, 49), w.STONE)
	for z in range(28, 74, 4): w._box("TileJoint", Vector3(48, 0.05, z), Vector3(47, 0.02, 0.025), w.STONE)
	_wall_gap(Vector3(24, 0, 49), 50, 8.5, true, 52, 8)
	_wall_gap(Vector3(48, 0, 24), 48, 8.5, false, 53, 6)
	w._box("MallEastWall", Vector3(72, 4.25, 49), Vector3(0.35, 8.5, 50), w.TEAL, true)
	for ends: Vector2 in [Vector2(24,45),Vector2(51,59),Vector2(65,72)]:
		w._box("MallSouthWall",Vector3((ends.x+ends.y)*0.5,4.25,74),Vector3(ends.y-ends.x,8.5,0.35),w.PLASTER,true)
	for x: float in [48,62]:
		w._box("TerminalDoorLintel",Vector3(x,6.5,74),Vector3(6,4,0.35),w.PLASTER,true)
		w._sign("TERMINAL  →",Vector3(x,3.5,73.7),5,PI)
	# Upper U route has two independent stairs; the atrium stays open to both floors.
	w._floor("MallNorthMezzanine", Vector3(48, 4.2, 32.5), Vector2(48, 9))
	w._floor("MallEastMezzanine", Vector3(68.5, 4.2, 52), Vector2(7, 30))
	w._floor("MallSouthMezzanine", Vector3(66, 4.2, 69), Vector2(12, 10))
	_rail(Vector3(24.2, 4.2, 37), Vector3(30.5, 4.2, 37))
	_rail(Vector3(35.5, 4.2, 37), Vector3(65, 4.2, 37))
	_rail(Vector3(65, 4.2, 37), Vector3(65, 4.2, 64))
	_rail(Vector3(60, 4.2, 64), Vector3(65, 4.2, 64))
	_rail(Vector3(60, 4.2, 69.5), Vector3(60, 4.2, 73.8))
	_rail(Vector3(24.2, 4.2, 28), Vector3(50, 4.2, 28))
	_rail(Vector3(56, 4.2, 28), Vector3(71.8, 4.2, 28))
	# No ceiling slab across stair wells. Skylight gives the central combat loop height.
	w._box("MallRoofNorth", Vector3(48, 8.6, 31), Vector3(48, 0.3, 14), w.DARK, true)
	w._box("MallRoofSouth", Vector3(48, 8.6, 68), Vector3(48, 0.3, 12), w.DARK, true)
	w._box("MallRoofWest", Vector3(30, 8.6, 50), Vector3(12, 0.3, 24), w.DARK, true)
	w._box("MallRoofEast", Vector3(68.5, 8.6, 50), Vector3(7, 0.3, 24), w.DARK, true)
	w._box("AtriumSkylight", Vector3(50.5, 10.0, 50), Vector3(29, 0.12, 24), Color("456e76"), false, 0.3)
	for x: float in [37, 46, 55, 64]:
		w._beam(Vector3(x, 9.7, 38), Vector3(x, 9.7, 62), 0.16, 0.3, w.DARK)
	for p: Vector3 in [Vector3(40, 0, 39), Vector3(62, 0, 39), Vector3(40, 0, 60), Vector3(62, 0, 60)]:
		w._box("AtriumColumn", p + Vector3(0, 4.2, 0), Vector3(0.65, 8.4, 0.65), w.TEAL, true)
	# Shops are rooms with usable entrances, furniture and specific economy stations.
	for spec: Array in [[32, 30, "FARMÁCIA"], [66, 43, "ARSENAL AURORA"], [31, 65, "CAFÉ DA CHUVA"], [66, 57, "OFICINA DE PRECISÃO"]]:
		var p := Vector3(spec[0], 0, spec[1])
		w._room(p, Vector2(10, 10), 3.7, str(spec[2]))
		w._sign(str(spec[2]), p + Vector3(0, 2.85, 5.2), 7.5)
		if p.x > 60: w._sign(str(spec[2]), p + Vector3(-5.2, 2.85, 0), 6.5, -PI / 2)
		w._lamp(p + Vector3(0, 3.1, 0), w.WARM, 8)
		w._box("ShopCounter", p + Vector3(2.7, 0.55, -2), Vector3(2.6, 1.1, 0.9), w.RUST, true)
		for level in range(3):
			w._box("StockShelf", p + Vector3(-2.5, 0.65 + level * 0.65, -3.8), Vector3(3, 0.08, 0.6), w.DARK)
			for item in range(4):
				w._box("ShopStock", p + Vector3(-3.4 + item * 0.6, 0.87 + level * 0.65, -3.8), Vector3(0.3, 0.36, 0.3), [w.PLASTER, w.TEAL, w.RUST][level])
	# A low planter/kiosk island breaks lines of sight without blocking the main aisles.
	w._box("AtriumPlanter", Vector3(51, 0.4, 48), Vector3(6, 0.8, 4), w.TEAL, true)
	for x: float in [49, 51, 53]: _bush(Vector3(x, 1.0, 48), 0.8)
	w._sign("AURORA", Vector3(51, 5.5, 48), 8)
	for x: float in [47.5, 54.5]: w._cylinder_between(Vector3(x, 5.9, 48), Vector3(x, 9.7, 48), 0.025, w.DARK)
	w._sign("SHOPPING AURORA", Vector3(23.7, 4.6, 52), 11, -PI / 2)
	w._sign("CINEMA  ↑", Vector3(53, 2.8, 25.1), 5)
	w._sign("JARDIM  ←", Vector3(29, 2.8, 47.7), 4)
	w._sign("MEZANINO • COFRE", Vector3(33, 5.7, 36.8), 5)
	for z: float in [44, 58]: w._bench(Vector3(58, 0, z))
	for p: Vector3 in [Vector3(45, 7.5, 44), Vector3(58, 7.5, 58), Vector3(48, 7.3, 32), Vector3(68, 7.3, 66)]:
		w._lamp(p, Color("a9d6cd"), 17)

func _cinema() -> void:
	w._floor("CinemaGround", Vector3(51, 0, 5), Vector2(42, 38))
	w._box("CinemaCarpet", Vector3(51, 0.025, 5), Vector3(41.8, 0.04, 37.8), RED.darkened(0.25))
	_wall_gap(Vector3(51, 0, 24), 42, 7.8, false, 53, 6)
	_wall_gap(Vector3(30, 0, 5), 38, 7.8, true, -7, 6, 7.2)
	w._box("CinemaBackWall", Vector3(51, 3.9, -14), Vector3(42, 7.8, 0.35), w.DARK, true)
	w._box("CinemaEastWall", Vector3(72, 3.9, 5), Vector3(0.35, 7.8, 38), w.DARK, true)
	w._box("CinemaRoof", Vector3(51, 8, 5), Vector3(42, 0.3, 38), w.DARK, true)
	# Two auditorium entrances plus the side-stage route prevent a single funnel.
	_wall_gap(Vector3(53, 0, 14), 38, 5.5, false, 57, 6)
	# The side corridor meets the auditorium through a second large exit at z=3.
	_wall_gap(Vector3(41, 0, 0), 28, 5.5, true, 3, 6)
	w._sign("CINE ÚLTIMA LUZ", Vector3(53, 3.4, 23.6), 11, PI)
	w._sign("SALA 01 • ÚLTIMA SESSÃO", Vector3(57, 3.2, 14.25), 8)
	w._sign("SAÍDA • OFICINA", Vector3(36, 3.5, 13.9), 5)
	# Projection room has two real doors and rewards; connected to the service stair.
	w._room(Vector3(35, 0, -10), Vector2(8, 7), 3.7, "ProjectionArchive")
	w._box("FilmRack", Vector3(32.3, 1.0, -11.7), Vector3(0.6, 2, 2.8), w.TEAL, true)
	for z: float in [-12.4, -11.5, -10.6]:
		w._cylinder("FilmCanister", Vector3(32.3, 2.05, z), 0.28, 0.1, w.PLASTER)
	w._sign("ARQUIVO", Vector3(35, 2.9, -6.3), 4.5)
	w._lamp(Vector3(35, 3.1, -10), w.WARM, 7)
	# Four rows in two banks share simple colliders, with wide center and flank aisles.
	for z: float in [-3, 1, 5, 9]:
		for x: float in [49, 64]:
			w._box("SeatRowCollision", Vector3(x, 0.5, z), Vector3(5.4, 1.0, 1.25), RED, true).visible = false
			for offset: float in [-1.8, 0, 1.8]:
				var p := Vector3(x + offset, 0, z)
				w._box("CinemaSeatBack", p + Vector3(0, 0.95, 0.4), Vector3(1.25, 1.4, 0.25), RED.lightened(0.08))
				w._box("CinemaSeatCushion", p + Vector3(0, 0.53, -0.18), Vector3(1.25, 0.26, 0.9), RED)
				for side: float in [-0.73, 0.73]: w._box("SeatArm", p + Vector3(side, 0.74, 0), Vector3(0.16, 0.15, 1.1), w.DARK)
	w._floor("CinemaStage", Vector3(56.5, 0.9, -10), Vector2(29, 5))
	var screen: MeshInstance3D = w._box("CinemaScreen", Vector3(57, 4.4, -13.72), Vector3(23, 5.2, 0.08), Color("89b2ab"), false, 0.5)
	var screen_quad := QuadMesh.new()
	screen_quad.size = Vector2(23, 5.2)
	screen.mesh = screen_quad
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded; void fragment(){vec2 p=UV-vec2(0.5); float moon=1.0-smoothstep(0.095,0.10,length((p-vec2(0.22,-0.17))*vec2(4.42,1.0))); float hills=smoothstep(0.08+sin(p.x*12.0)*0.10,0.09+sin(p.x*12.0)*0.10,p.y); vec3 c=mix(vec3(0.17,0.29,0.32),vec3(0.07,0.13,0.17),hills); c+=vec3(0.43,0.43,0.29)*moon; c*=0.94+0.06*sin(UV.y*600.0); ALBEDO=c; }"
	var film := ShaderMaterial.new()
	film.shader = shader
	screen.material_override = film
	w._sign("O ÚLTIMO FAROL", Vector3(57, 2.8, -13.62), 12)
	for x: float in [43.5, 70]:
		w._box("StageCurtain", Vector3(x, 4, -13.3), Vector3(2.1, 7.4, 0.35), RED)
	w._box("CeilingProjector", Vector3(57, 6.8, 10), Vector3(1.1, 0.6, 1.4), w.DARK)
	w._box("ProjectorLens", Vector3(57, 6.8, 9.25), Vector3(0.3, 0.3, 0.1), w.WARM, false, 1.2)
	for x: float in [43, 70]:
		w._box("CinemaSpeaker", Vector3(x, 3.3, -12), Vector3(0.75, 1.8, 0.8), w.DARK)
		for z: float in [-7, 0, 7]:
			w._box("AisleGuideLight", Vector3(x, 0.11, z), Vector3(0.12, 0.13, 1.4), Color("d6aa74"), false, 0.9)
	# Ticket booth and concession counter leave a 5m-wide cross-foyer escape route.
	w._box("TicketCounter", Vector3(40, 0.65, 22), Vector3(8, 1.3, 1.2), w.RUST, true)
	w._sign("BILHETERIA", Vector3(40, 2.4, 22.5), 6, PI)
	w._box("PopcornCounter", Vector3(66, 0.65, 22), Vector3(7, 1.3, 1.2), w.TEAL, true)
	w._sign("PIPOCA • CAFÉ", Vector3(66, 2.6, 22.5), 5, PI)
	for x: float in [63.5, 66, 68.5]:
		w._box("PopcornTub", Vector3(x, 1.65, 22), Vector3(0.5, 0.7, 0.5), w.WARM)
	for x: float in [45, 61, 69]:
		w._box("FilmPosterFrame", Vector3(x, 2.3, 23.78), Vector3(2.1, 2.6, 0.12), w.RUST)
		w._sign("ÚLTIMA LUZ", Vector3(x, 2.5, 23.68), 1.8, PI)
	w._lamp(Vector3(53, 4.8, 19), w.WARM, 18)
	w._lamp(Vector3(57, 5.5, -8), Color("8cc4d0"), 19)
	w._lamp(Vector3(57, 5.5, 9), Color("b78eac"), 17)

func _wall_gap(center: Vector3, length: float, height: float, along_z: bool, opening: float, width: float, clearance: float = 4.0) -> void:
	var axis := center.z if along_z else center.x
	for span: Vector2 in [Vector2(axis - length / 2, opening - width / 2), Vector2(opening + width / 2, axis + length / 2)]:
		if span.y <= span.x: continue
		var p := center + Vector3(0, height / 2, 0)
		if along_z: p.z = (span.x + span.y) / 2
		else: p.x = (span.x + span.y) / 2
		var size := Vector3(0.35, height, span.y - span.x) if along_z else Vector3(span.y - span.x, height, 0.35)
		w._box("DistrictWall", p, size, w.TEAL, true)
	# Keep 4m of clearance, including gates and bosses.
	var lintel := center + Vector3(0, clearance + (height - clearance) / 2, 0)
	if along_z: lintel.z = opening
	else: lintel.x = opening
	if height > clearance:
		w._box("DoorHeader", lintel, Vector3(0.35, height - clearance, width) if along_z else Vector3(width, height - clearance, 0.35), w.RUST, true)

func _rail(a: Vector3, b: Vector3) -> void:
	w._beam(a + Vector3.UP * 0.55, b + Vector3.UP * 0.55, 0.15, 1.1, w.TEAL, true)
	w._beam(a + Vector3.UP * 1.15, b + Vector3.UP * 1.15, 0.2, 0.1, w.WARM)

func _greenhouse() -> void:
	# Transparent panes above solid sills retain an actual sheltered interior.
	w._box("GreenhousePaving", Vector3(-8, 0.07, 61), Vector3(8.9, 0.035, 7.9), w.STONE)
	for ends: Array in [
		[Vector3(-12.5, 0, 57), Vector3(-3.5, 0, 57)],
		[Vector3(-3.5, 0, 57), Vector3(-3.5, 0, 65)],
		[Vector3(-12.5, 0, 57), Vector3(-12.5, 0, 59)],
		[Vector3(-12.5, 0, 63), Vector3(-12.5, 0, 65)],
		[Vector3(-12.5, 0, 65), Vector3(-10, 0, 65)],
		[Vector3(-6, 0, 65), Vector3(-3.5, 0, 65)]
	]:
		var a: Vector3 = ends[0]
		var b: Vector3 = ends[1]
		w._beam(a + Vector3.UP * 0.35, b + Vector3.UP * 0.35, 0.15, 0.7, w.TEAL, true)
		var pane: MeshInstance3D = w._box("GreenhousePane", (a + b) / 2 + Vector3.UP * 2.25, Vector3(0.08, 3.1, a.distance_to(b)), Color("639186"), true)
		pane.look_at_from_position(pane.position, b + Vector3.UP * 2.25)
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.32, 0.52, 0.46, 0.24)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.cull_mode = BaseMaterial3D.CULL_DISABLED
		pane.material_override = glass
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for p: Vector3 in [a, b]: w._box("GreenhouseFrame", p + Vector3.UP * 2, Vector3(0.12, 4, 0.12), w.RUST)
		w._beam(a + Vector3.UP * 3.9, b + Vector3.UP * 3.9, 0.14, 0.18, w.RUST)
	w._box("GreenhouseRoof", Vector3(-8, 4, 61), Vector3(9.4, 0.16, 8.4), w.TEAL, true)

func _tree(p: Vector3) -> void:
	w._cylinder("GardenTrunk", p + Vector3.UP * 2, 0.3, 4, w.RUST, true)
	for side: float in [-1, 1]:
		w._cylinder_between(p + Vector3.UP * 2.5, p + Vector3(side * 1.3, 4, 0.4), 0.12, w.RUST)
	_bush(p + Vector3.UP * 4.8, 2.0)
	_bush(p + Vector3(1.3, 4.3, 0.4), 1.3)

func _bush(p: Vector3, radius: float) -> void:
	var node := MeshInstance3D.new()
	node.name = "GardenFoliage"
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 1.5
	mesh.radial_segments = 10
	mesh.rings = 4
	node.mesh = mesh
	node.position = p
	node.material_override = w._material(LEAF)
	w._geometry.add_child(node)
	w._vegetation.append(node)

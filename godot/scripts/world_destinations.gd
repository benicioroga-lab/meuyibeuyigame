extends RefCounted
## Two purpose-built destinations and physical upgrade stations for every district.
const REGION_IDS := ["cisterna","terminal"]
const Perks = preload("res://data/district_perks.gd")
const LANDMARKS := {"cisterna":Vector3(-37,-1.8,53),"painel_bombas":Vector3(-39,-1.8,46),"terminal":Vector3(48,0.2,94),"despacho":Vector3(62,0.2,93)}
var w: Node3D

static func register(world: Node3D) -> void:
	world.regions.append_array([
		{"id":"cisterna","name":"Casa das Bombas","center":Vector3(-37,-2,53),"unlock_cost":360,"unlock_round":3},
		{"id":"terminal","name":"Terminal da Madrugada","center":Vector3(48,0,94),"unlock_cost":600,"unlock_round":5}
	])
	world.spawn_points.append_array([Vector3(-42,-1.75,42),Vector3(-43,-1.75,66),Vector3(-30,-1.75,61),Vector3(32,0.25,98),Vector3(62,0.25,101),Vector3(62,0.25,83)])
	world.points_of_interest.append_array([
		{"id":"porta_cisterna","type":"door","name":"Casa das Bombas","position":Vector3(-19,-0.3,52),"region_id":"cisterna","cost":360},
		{"id":"porta_cisterna_volta","type":"door","name":"Casa das Bombas","position":Vector3(-19,-0.3,66),"region_id":"cisterna","cost":360},
		{"id":"porta_terminal","type":"door","name":"Terminal da Madrugada","position":Vector3(48,0.2,78),"region_id":"terminal","cost":600},
		{"id":"porta_terminal_volta","type":"door","name":"Terminal da Madrugada","position":Vector3(62,0.2,78),"region_id":"terminal","cost":600},
		{"id":"desafio_bombas","type":"challenge","name":"Restabelecer a pressão","position":Vector3(-37,-1.8,53),"region_id":"cisterna","cost":0,"target":35,"duration":85,"mode":"hold","radius":7.0,"pressure":true},
		{"id":"desafio_terminal","type":"challenge","name":"Último embarque","position":Vector3(48,0.2,94),"region_id":"terminal","cost":0,"target":18,"duration":100,"pressure":true},
		{"id":"reserva_manutencao","type":"cache","name":"Armário de manutenção","position":Vector3(-45,-1.8,62),"region_id":"cisterna","cost":0},
		{"id":"bau_despacho","type":"chest","name":"Cofre do despacho","position":Vector3(65,0.2,91),"region_id":"terminal","cost":160}
	])
	for id: String in Perks.PERKS:
		var perk: Dictionary = Perks.PERKS[id]
		world.points_of_interest.append({"id":"estacao_"+id,"type":"perk_station","name":perk.name,"position":perk.position,"region_id":perk.region,"perk_id":id,"cost":perk.cost})

static func gates(world: Node3D) -> void:
	for z: float in [52,66]: world._gate("cisterna",Vector3(-20,-0.67,z),5,true,"porta_cisterna" if z == 52 else "porta_cisterna_volta")
	for x: float in [48,62]: world._gate("terminal",Vector3(x,0,78),6,false,"porta_terminal" if x == 48 else "porta_terminal_volta")

func build(world: Node3D) -> void:
	w = world
	_pump_house()
	_terminal()
	for id: String in Perks.PERKS: _station(id)

func _pump_house() -> void:
	w._floor("PumpHouseFoundation",Vector3(-39,-2,54),Vector2(28,34))
	for z: float in [52,66]:
		w._floor("PumpAccessLanding",Vector3(-15,0,z),Vector2(2,5))
		w._ramp("PumpAccessStairs",Vector3(-16,0,z),Vector3(-28,-2,z),5)
		for side: float in [-2.5,2.5]:
			w._beam(Vector3(-16,1.1,z+side),Vector3(-28,-0.9,z+side),0.14,0.16,w.TEAL,true)
	w._box("PumpBackWall",Vector3(-53,1,54),Vector3(0.4,6,34),w.BRICK,true)
	w._box("PumpNorthWall",Vector3(-39,1,37),Vector3(28,6,0.4),w.TEAL,true)
	w._box("PumpSouthWall",Vector3(-39,1,71),Vector3(28,6,0.4),w.TEAL,true)
	for z: float in [40,46,58,70]:
		w._box("PumpPortalPier",Vector3(-25,1,z),Vector3(0.45,6,3),w.PLASTER,true)
	# Curved roof ribs, copper pipes and round pressure tanks define the silhouette.
	for z: float in [38,46,54,62,70]: _arch(Vector3(-39,3.2,z),14,3.2,0.22,w.RUST)
	w._box("PumpRoof",Vector3(-39,6.4,54),Vector3(28,0.22,34),w.DARK,true)
	for at: Vector3 in [Vector3(-46,-2,44),Vector3(-32,-2,43),Vector3(-47,-2,64)]:
		w._cylinder("PressureTank",at+Vector3.UP*1.7,2.2,3.4,w.TEAL,true)
		_sphere("TankDome",at+Vector3.UP*3.4,Vector3(2.2,0.65,2.2),w.TEAL)
		for y: float in [0.4,2.7]: _torus(at+Vector3.UP*y,2.22,0.07,w.RUST)
		w._cylinder_between(at+Vector3(0,3.7,0),at+Vector3(0,4.8,0),0.22,w.RUST)
		w._cylinder_between(at+Vector3(0,4.8,0),Vector3(-51,2.8,at.z),0.22,w.RUST)
		var gauge: MeshInstance3D = w._cylinder("PressureGauge",at+Vector3(0,2.2,2.23),0.29,0.1,w.PLASTER)
		gauge.rotation.x = PI/2
		w._box("GaugeNeedle",at+Vector3(0,2.25,2.31),Vector3(0.02,0.24,0.025),w.DARK).rotation.z = -0.55
	for z: float in [42,49,57,65]:
		w._cylinder_between(Vector3(-52,0.3,z),Vector3(-52,3.6,z),0.16,w.RUST)
		w._puddle(Vector3(-41,-1.98,z),Vector2(3.5,1.8))
	w._sign("CASA DAS BOMBAS / 03",Vector3(-24.7,2.7,52),9,PI/2)
	w._sign("CONTROLE DE PRESSÃO",Vector3(-39,1.6,45.5),5)
	w._lamp(Vector3(-39,3.2,52),Color("6eb2bf"),10)
	w._lamp(Vector3(-47,2.8,62),Color("cd945f"),8)

func _terminal() -> void:
	w._floor("TerminalGround",Vector3(48,0,94),Vector2(48,32))
	for x: float in [48,62]:
		w._floor("TerminalPassage",Vector3(x,0,76),Vector2(6,8))
		for side: float in [-3,3]: w._edge(Vector3(x+side,0,72),Vector3(x+side,0,80),2.5)
	for x: float in [24,72]: w._edge(Vector3(x,0,80),Vector3(x,0,110),2.8)
	w._edge(Vector3(24,0,110),Vector3(72,0,110),3.4)
	# Two grounded tram bodies create flanking lanes instead of one empty square.
	for at: Vector3 in [Vector3(35,0,91),Vector3(54,0,103)]: _tram(at)
	for x: float in [29,40,48,62,70]:
		w._cylinder("PlatformPillar",Vector3(x,2.3,82),0.14,4.6,w.TEAL,true)
		w._beam(Vector3(x,4.6,80),Vector3(x,5.4,98),0.14,0.2,w.TEAL)
	w._box("PlatformCanopy",Vector3(48,5.2,87),Vector3(48,0.14,14),w.DARK)
	for x: float in [44,66]:
		w._bench(Vector3(x,0,83))
		w._lamp(Vector3(x,4.7,86),Color("cfb984"),11)
	w._room(Vector3(65,0,91),Vector2(10,10),3.6,"DispatchOffice")
	w._sign("DESPACHO",Vector3(65,2.9,96.2),5)
	w._sign("TERMINAL / ÚLTIMO EMBARQUE",Vector3(48,4,80),14,PI)
	w._sign("02:17  /  SEM PREVISÃO",Vector3(47,3,91),7)
	for z: float in [96,109]:
		for x: float in [28,30]: w._box("TrackRail",Vector3(x,0.035,(z+80)*0.5),Vector3(0.08,0.05,z-80),w.RUST)
	for z: int in range(80,110,2): w._box("RailSleeper",Vector3(29,0.045,z),Vector3(3.6,0.06,0.18),w.DARK)

func _tram(at: Vector3) -> void:
	w._box("TramBody",at+Vector3.UP*1.3,Vector3(3.1,2.0,10),Color("596f68"),true)
	_sphere("TramNose",at+Vector3(0,1.65,-4.75),Vector3(1.55,1.2,0.8),Color("596f68"))
	# Roof is a smooth extruded half-cylinder with rounded nose and metal seams.
	var roof: MeshInstance3D = w._cylinder("TramRoof",at+Vector3.UP*2.28,1.57,9.6,w.TEAL)
	roof.rotation.x = PI/2
	roof.scale.x = 1
	roof.scale.z = 0.4
	for side: float in [-1,1]:
		for z: float in [-3,-1,1,3]:
			w._box("TramGlass",at+Vector3(side*1.57,1.9,z),Vector3(0.025,0.85,1.55),Color("0e2028"))
			w._box("TramWindowRim",at+Vector3(side*1.58,1.42,z),Vector3(0.03,0.07,1.68),w.RUST)
		for z: float in [-3.2,3.2]:
			var wheel: MeshInstance3D = w._cylinder("TramWheel",at+Vector3(side*1.2,0.32,z),0.39,0.42,w.DARK)
			wheel.rotation.z = PI/2
	w._box("TramWindshield",at+Vector3(0,2,-5.42),Vector3(2.35,0.9,0.05),Color("17323a"))
	for x: float in [-0.85,0.85]:
		var light: MeshInstance3D = w._cylinder("TramHeadlamp",at+Vector3(x,1.05,-5.36),0.17,0.08,Color("a18a66"),false,0.18)
		light.rotation.x = PI/2

func _station(id: String) -> void:
	var p: Dictionary = Perks.PERKS[id]
	var at: Vector3 = p.position + Vector3(0.85,-0.2,0)
	var color := Color(p.color)
	w._cylinder("PerkStationBase",at+Vector3.UP*0.16,0.46,0.32,w.DARK,true)
	w._box("PerkStationCabinet",at+Vector3.UP*0.85,Vector3(0.7,1.25,0.48),w.TEAL,true)
	w._box("PerkStationDisplay",at+Vector3(0,1.22,0.254),Vector3(0.52,0.42,0.035),color,false,0.7)
	_torus(at+Vector3.UP*1.58,0.24,0.045,color)
	w._sign(p.name.to_upper(),at+Vector3(0,1.95,0),2.8)
	w._box("StationContactShadow",at+Vector3.UP*0.016,Vector3(1.15,0.012,0.95),w.DARK)

func _arch(at: Vector3, radius: float, height: float, thickness: float, color: Color) -> void:
	for i: int in range(16):
		var a := float(i)*PI/16
		var b := float(i+1)*PI/16
		w._cylinder_between(at+Vector3(cos(a)*radius,sin(a)*height,0),at+Vector3(cos(b)*radius,sin(b)*height,0),thickness,color)

func _sphere(label: String, at: Vector3, size: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := SphereMesh.new()
	mesh.radius = 1
	mesh.height = 2
	mesh.radial_segments = 24
	mesh.rings = 12
	node.mesh = mesh
	node.position = at
	node.scale = size
	node.material_override = w._material(color)
	w._geometry.add_child(node)

func _torus(at: Vector3, radius: float, thickness: float, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius-thickness
	mesh.outer_radius = radius+thickness
	mesh.rings = 24
	mesh.ring_segments = 6
	node.mesh = mesh
	node.position = at
	node.material_override = w._material(color)
	w._geometry.add_child(node)

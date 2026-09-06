extends RefCounted
## Architectural detail and occlusion share the authored solids, never fill doorways.
var w: Node3D
var _contact_material: ShaderMaterial

func build(world: Node3D) -> void:
	w = world
	var originals: Array = w._geometry.get_children()
	for node: Node in originals:
		if not node is MeshInstance3D or not node.visible or not node.mesh is BoxMesh: continue
		var size: Vector3 = node.mesh.size
		var solid := node.get_child_count() > 0 and node.get_child(0) is StaticBody3D
		if solid and size.x > 2 and size.y > 2 and size.z > 2 and node.get_meta("authored_label","") == "OccupiedHouse":
			_facade(node.position - Vector3.UP * size.y * 0.5,size)
		if size.y > 0.16 and size.x > 0.15 and size.z > 0.15 and size.x < 4 and size.z < 4:
			node.mesh = preload("res://scripts/weapon_geometry.gd").chamfer_box(size)
		if solid and size.y > 0.2 and size.x < 15 and size.z < 15 and node.position.y-size.y/2 > -4.2:
			_contact(node.position - Vector3.UP * (size.y/2-0.012),Vector2(size.x+0.7,size.z+0.7))
		if solid:
			var extents := [size.x,size.y,size.z]
			extents.sort()
			if extents[1] >= 2 and extents[2] >= 5 and extents[0] > 0.1:
				var occluder := OccluderInstance3D.new()
				occluder.name = "SolidOcclusion"
				var shape := BoxOccluder3D.new()
				shape.size = size * 0.96
				occluder.occluder = shape
				node.add_child(occluder)
	# Software occluders follow the solid meshes and preserve every authored opening.
	w.get_tree().root.use_occlusion_culling = true

func _contact(at: Vector3, size: Vector2) -> void:
	if _contact_material == null:
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
void fragment() {
 vec2 p = abs(UV * 2.0 - 1.0);
 float contact = 1.0 - smoothstep(0.60,1.0,max(p.x,p.y));
 ALBEDO = vec3(0.018,0.026,0.030);
 ALPHA = contact * 0.32;
}
"""
		_contact_material = ShaderMaterial.new()
		_contact_material.shader = shader
	var node := MeshInstance3D.new()
	node.name = "LocalContactOcclusion"
	var mesh := PlaneMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = _contact_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w._geometry.add_child(node)

func _facade(at: Vector3, size: Vector3) -> void:
	# Deep window sills, lintels, air conditioning and rooftop cisterns create relief.
	for floor_index: int in range(maxi(1,int(size.y/2.6))):
		var y := 1.4+floor_index*2.6
		for side: float in [-0.25,0.25]:
			var center := at+Vector3(size.x*side,y,size.z/2+0.13)
			w._box("StoneWindowSill",center+Vector3(0,-0.69,0.10),Vector3(1.2,0.13,0.32),w.PLASTER)
			w._box("MouldedWindowLintel",center+Vector3(0,0.68,0),Vector3(1.2,0.13,0.18),w.RUST)
		if floor_index == 0:
			var ac := at+Vector3(size.x*0.27,y-0.85,size.z/2+0.30)
			w._box("AirConditioner",ac,Vector3(0.8,0.45,0.45),w.PLASTER)
			var fan: MeshInstance3D = w._cylinder("ACFan",ac+Vector3(0.1,0,0.24),0.16,0.035,w.DARK)
			fan.rotation.x = PI/2
			for rib: int in range(4): w._box("ACVent",ac+Vector3(-0.25+rib*0.045,0,0.24),Vector3(0.017,0.26,0.025),w.DARK)
	var tank_at := at+Vector3(-size.x*0.23,size.y+0.58,0)
	w._cylinder("RooftopCistern",tank_at,0.75,1.05,Color("374b57"))
	var dome: MeshInstance3D = w._cylinder("CisternCap",tank_at+Vector3.UP*0.57,0.78,0.12,w.DARK)
	dome.mesh.top_radius = 0.48
	w._cylinder_between(tank_at+Vector3(0.7,0,0),at+Vector3(size.x/2+0.16,0.3,0),0.045,w.RUST)

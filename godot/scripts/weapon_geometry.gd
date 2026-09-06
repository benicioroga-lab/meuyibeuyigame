extends RefCounted

## Shared hard-surface geometry for first-person weapons, bench previews and loot.
static func chamfer_box(size: Vector3) -> ArrayMesh:
	var half := size * 0.5
	var bevel := minf(minf(size.x, size.y), size.z) * 0.14
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for layer: int in range(4):
		var edge := layer == 0 or layer == 3
		var x: float = half.x - (bevel if edge else 0)
		var y: float = half.y - (bevel if edge else 0)
		var z: float = [-half.z, -half.z + bevel, half.z - bevel, half.z][layer]
		var cut := bevel * 0.6
		var ring := PackedVector3Array()
		for p: Vector2 in [Vector2(-x+cut,-y),Vector2(x-cut,-y),Vector2(x,-y+cut),Vector2(x,y-cut),Vector2(x-cut,y),Vector2(-x+cut,y),Vector2(-x,y-cut),Vector2(-x,-y+cut)]:
			ring.append(Vector3(p.x,p.y,z))
		rings.append(ring)
	for layer: int in range(3):
		for i: int in range(8):
			var j := (i+1)%8
			_triangle(surface, rings[layer][i], rings[layer+1][j], rings[layer][j])
			_triangle(surface, rings[layer][i], rings[layer+1][i], rings[layer+1][j])
	for i: int in range(8):
		_triangle(surface, Vector3(0,0,-half.z), rings[0][i], rings[0][(i+1)%8])
		_triangle(surface, Vector3(0,0,half.z), rings[3][(i+1)%8], rings[3][i])
	surface.generate_normals()
	surface.index()
	return surface.commit()

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)

extends SceneTree


func _initialize() -> void:
	var vertices: PackedVector3Array = []
	var colors: PackedColorArray = []
	var normals: PackedVector3Array = []
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces: int = 0
	for line: String in FileAccess.get_file_as_string("res://assets/roadster.obj").split("\n"):
		var parts: PackedStringArray = line.split(" ", false)
		if parts.is_empty() or parts[0].begins_with("#"):
			continue
		match parts[0]:
			"v":
				if parts.size() < 7:
					push_error("The source roadster must contain RGB vertex colors.")
					quit(1)
					return
				vertices.append(Vector3(float(parts[1]), float(parts[2]), float(parts[3])))
				colors.append(Color(float(parts[4]), float(parts[5]), float(parts[6])))
			"vn":
				normals.append(Vector3(float(parts[1]), float(parts[2]), float(parts[3])))
			"f":
				for triangle: int in range(2, parts.size() - 1):
					for corner: int in [1, triangle + 1, triangle]:
						var indices: PackedStringArray = parts[corner].split("/")
						var vertex_index: int = int(indices[0]) - 1
						surface.set_color(colors[vertex_index])
						if indices.size() > 2 and not indices[2].is_empty():
							surface.set_normal(normals[int(indices[2]) - 1])
						surface.add_vertex(vertices[vertex_index])
					faces += 1
	surface.index()
	if normals.is_empty():
		surface.generate_normals()
	var mesh: ArrayMesh = surface.commit()
	var result: Error = ResourceSaver.save(mesh, "res://assets/roadster-colored.res")
	if result != OK:
		push_error("Roadster conversion failed: " + error_string(result))
		quit(1)
		return
	print("Preserved %d colored vertices and %d triangles." % [vertices.size(), faces])
	quit()

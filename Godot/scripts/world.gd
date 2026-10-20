class_name RacerWorld
extends Node3D

const ROAD_CHUNK_LENGTH: float = 48.0
const FINISH_EXTENSION: float = 960.0

var simulation: RacerSimulation
var camera: Camera3D = Camera3D.new()
var hero: RacerCar
var road: Node3D = Node3D.new()
var actors: Node3D = Node3D.new()
var environment: Environment = Environment.new()
var sun: MeshInstance3D
var settings: Dictionary
var palette: Dictionary
var track_revision: int = -1
var coast_color: Color = Color("#22d3ee")
var time: float = 0.0
var camera_offset: Vector3 = Vector3(0, 3, 8)
var presentation_distance: float = 0.0
var traffic_nodes: Array[RacerCar] = []
var obstacle_nodes: Array[Node3D] = []
var road_chunks: Array[Node3D] = []
var cached_chunks: Dictionary[int, Node3D] = {}
var road_material: ShaderMaterial = ShaderMaterial.new()
var terrain_material: ShaderMaterial = ShaderMaterial.new()
var chunks_built: int = 0
var level_ready: bool = false
var camera_look_offset: Vector3 = Vector3(0, 1.05, -26)
var sky: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
var sun_material: ShaderMaterial = ShaderMaterial.new()
var environment_weights: Vector3 = Vector3(1, 0, 0)
var environment_start: Vector3 = Vector3(1, 0, 0)
var environment_target: Vector3 = Vector3(1, 0, 0)
var environment_elapsed: float = 3.0
var facade_materials: Array[ShaderMaterial] = []
var display_materials: Array[ShaderMaterial] = []
var ambient_nodes: Array[Node3D] = []


func setup(race: RacerSimulation, preferences: Dictionary, colors: Dictionary) -> void:
	set_process(false)
	simulation = race
	settings = preferences
	palette = colors
	add_child(road)
	add_child(actors)
	sky.sky_top_color = Color("#05031b")
	sky.sky_horizon_color = Color("#130a25")
	sky.ground_bottom_color = Color("#020511")
	sky.ground_horizon_color = Color("#160b29")
	sky.sun_angle_max = 0
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#8281bf")
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = not bool(settings.reduce_flashes) and int(settings.quality) != 1
	environment.glow_intensity = 0.65
	environment.fog_enabled = true
	environment.fog_light_color = Color("#252044")
	environment.fog_density = 0.0014
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -20, 0)
	light.light_color = Color("#c0b9ff")
	light.light_energy = 1.4
	add_child(light)
	camera.fov = 44
	camera.near = 0.25
	camera.far = 3000
	add_child(camera)
	camera.current = true
	hero = make_car(Color(str(palette.primary)), Color(str(palette.secondary)), true)
	add_child(hero)
	sun = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(600, 600)
	sun.mesh = quad
	sun_material.shader = preload("res://shaders/sun.gdshader")
	sun.material_override = sun_material
	add_child(sun)
	var post_layer: CanvasLayer = CanvasLayer.new()
	post_layer.layer = 0
	add_child(post_layer)
	var post_rect: ColorRect = ColorRect.new()
	post_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var post_material: ShaderMaterial = ShaderMaterial.new()
	post_material.shader = preload("res://shaders/post_process.gdshader")
	post_material.set_shader_parameter("soften_effects",
		bool(settings.reduce_flashes) or bool(settings.reduce_motion))
	post_rect.material = post_material
	post_layer.add_child(post_rect)
	apply_settings()
	road_material.shader = preload("res://shaders/road.gdshader")
	terrain_material.shader = preload("res://shaders/grid.gdshader")
	var neon_colors: Array[Color] = [coast_color, Color("#ff2d95"), Color("#8b5cf6"),
		Color("#ff9f1c"), Color("#34d399"), Color("#168bff")]
	for index: int in range(neon_colors.size()):
		var facade: ShaderMaterial = ShaderMaterial.new()
		facade.shader = preload("res://shaders/city_facade.gdshader")
		var display: ShaderMaterial = ShaderMaterial.new()
		display.shader = preload("res://shaders/city_display.gdshader")
		for material: ShaderMaterial in [facade, display]:
			material.set_shader_parameter("accent", neon_colors[index])
			material.set_shader_parameter("secondary", neon_colors[(index + 1) % neon_colors.size()])
			material.set_shader_parameter("variation", index / 6.0)
		facade_materials.append(facade)
		display_materials.append(display)
	apply_settings()
	track_revision = simulation.track.revision
	environment_target = theme_weights(str(simulation.track.at_distance(simulation.distance).environment))
	environment_weights = environment_target
	environment_start = environment_target
	update_environment(str(simulation.track.at_distance(simulation.distance).environment), 0)


func prepare_level(progress: Callable) -> void:
	var last: int = ceili((simulation.track.total_length + FINISH_EXTENSION) / ROAD_CHUNK_LENGTH)
	for index: int in range(-3, last + 1):
		build_road_chunk(index)
		if (index + 4) % 4 == 0:
			progress.call(float(index + 4) / float(last + 4))
			await get_tree().process_frame
	for i: int in range(RacerSimulation.MAX_TRAFFIC):
		var car: RacerCar = make_car(Color("#168bff"), Color("#22d3ee"))
		actors.add_child(car)
		car.visible = false
		traffic_nodes.append(car)
	for i: int in range(RacerSimulation.MAX_OBSTACLES):
		var barrier: Node3D = Node3D.new()
		box(barrier, Vector3(1.6, 0.8, 0.4), Vector3(0, 0.4, 0), neon(Color("#ff8a00")))
		actors.add_child(barrier)
		barrier.visible = false
		obstacle_nodes.append(barrier)
	level_ready = true
	_process(0)
	progress.call(1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	set_process(true)


func apply_settings() -> void:
	environment.glow_enabled = not bool(settings.reduce_flashes) and int(settings.quality) != 1
	var accent: Color = Color("#22d3ee")
	if int(settings.color_palette) == 1:
		accent = Color("#168bff")
	elif int(settings.color_palette) == 2:
		accent = Color("#34d399")
	coast_color = accent
	for material: ShaderMaterial in facade_materials + display_materials:
		material.set_shader_parameter("motion_strength", 0.0 if bool(settings.reduce_motion) or bool(settings.reduce_flashes) else 1.0)
		material.set_shader_parameter("pulse_strength", 0.0 if bool(settings.reduce_flashes) else 1.0)


func _process(delta: float) -> void:
	if simulation == null or not level_ready:
		return
	time += delta if simulation.phase != "paused" else 0
	update_background()
	var distance: float = simulation.render_distance()
	if simulation.phase == "finished":
		presentation_distance = minf(simulation.track.total_length + FINISH_EXTENSION / 2,
			presentation_distance + maxf(38, simulation.speed) * minf(delta, 0.1))
		distance = maxf(distance, presentation_distance)
	else:
		presentation_distance = distance
	var frame: Transform3D = simulation.track.actor_frame(distance, simulation.render_lateral(), simulation.split_side)
	hero.transform = frame
	if simulation.wipeout > 0:
		hero.transform = wipeout_transform(frame)
	hero.update_effects(simulation.steering_input if simulation.wipeout == 0 else 0.0,
		simulation.speed, simulation.boosting and simulation.phase == "racing", simulation.braking_input > 0.2, simulation.slip, time,
		bool(settings.reduce_motion), bool(settings.reduce_flashes))
	hero.set_effects_paused(simulation.phase == "paused")
	hero.visible = true
	var ratio: float = simulation.speed / float(simulation.config.maximum_speed)
	var desired: Vector3 = Vector3(0, 2.6 + ratio * 0.25, 7.65 + ratio * 1.4)
	var stage: Dictionary = simulation.track.sections[simulation.stage_id]
	if simulation.stage_id in ["city-axis-tunnel", "skyline-2"]:
		var in_stage: float = simulation.distance - simulation.stage_start
		var tunnel_blend: float = smoothstep(60, 120, in_stage) \
			* (1 - smoothstep(float(stage.length) - 96, float(stage.length) - 36, in_stage))
		desired.y -= tunnel_blend * 0.8
	camera_offset = camera_offset.lerp(desired, 1 - exp(-8 * delta))
	var look: Vector3 = Vector3(simulation.steering_input * (0.6 if bool(settings.reduce_motion) else 1.8),
		1.05, -(26 + ratio * 8))
	camera_look_offset = camera_look_offset.lerp(look, 1 - exp(-12 * delta))
	var camera_basis: Basis = Basis(Vector3.UP, atan2(-frame.basis.x.z, frame.basis.x.x))
	camera.position = frame.origin + camera_basis * camera_offset
	camera.look_at(frame.origin + camera_basis * camera_look_offset, Vector3.UP)
	var boost_fov: float = 7.0 if simulation.boosting and not bool(settings.reduce_motion) else 0.0
	camera.fov = lerpf(camera.fov, 44 + ratio * 6 + boost_fov, 1 - exp(-5 * delta))
	sun.position = camera.position + -frame.basis.z * 1400 + Vector3(0, 170, 0)
	sun.look_at(camera.position)
	var sample: Dictionary = simulation.track.at_distance(distance)
	update_environment(str(sample.environment), delta if simulation.phase != "paused" else 0.0)
	update_road_visibility(distance)
	update_actors()


func wipeout_transform(frame: Transform3D) -> Transform3D:
	var duration: float = simulation.wipeout_duration
	var elapsed: float = clampf(duration - simulation.wipeout, 0, duration)
	var severity: float = simulation.wipeout_severity
	var direction: float = simulation.wipeout_direction
	var reduced: bool = bool(settings.reduce_motion)
	var air_time: float = 0.85 + 0.35 * severity
	var peak: float = 0.35 if reduced else 1.0 + 1.1 * severity
	var lift: float = 0.0
	if elapsed < air_time:
		var u: float = elapsed / air_time
		lift = 4 * peak * u * (1 - u)
	elif elapsed < air_time + 0.4:
		var u: float = (elapsed - air_time) / 0.4
		lift = 4 * peak * 0.18 * u * (1 - u)
	var roll: float = (direction * TAU * (2 if severity > 0.6 else 1)
		* smoothstep(0, air_time + 0.15, elapsed)) if not reduced else 0.0
	var spin: float = (-direction * TAU * (1 + severity)
		* (1 - pow(1 - elapsed / duration, 3))) if not reduced else 0.0
	var pitch: float = sin(elapsed * 9) * 0.35 * (1 - elapsed / duration) if not reduced else 0.0
	var result: Transform3D = frame
	result.basis = frame.basis * Basis(Vector3.UP, spin) * Basis(Vector3.FORWARD, roll) * Basis(Vector3.RIGHT, pitch)
	var pivot: Vector3 = Vector3(0, float(hero.get_meta("center_height")), 0)
	result.origin += Vector3.UP * lift + frame.basis * pivot - result.basis * pivot
	return result


func theme_weights(id: String) -> Vector3:
	if id == "sunset-coast":
		return Vector3(1, 0, 0)
	if id in ["neon-city", "violet-skyway"]:
		return Vector3(0, 1, 0)
	return Vector3(0, 0, 1)


func update_environment(id: String, delta: float) -> void:
	var target: Vector3 = theme_weights(id)
	if target != environment_target:
		environment_start = environment_weights
		environment_target = target
		environment_elapsed = 0
	environment_elapsed = minf(3, environment_elapsed + delta)
	environment_weights = environment_start.lerp(environment_target, smoothstep(0, 3, environment_elapsed))
	sun.visible = environment_weights.x > 0.001
	sun_material.set_shader_parameter("opacity", environment_weights.x)
	sky.sky_horizon_color = Color("#130a25") * environment_weights.x \
		+ Color("#080e25") * environment_weights.y + Color("#071b28") * environment_weights.z
	environment.fog_light_color = Color("#252044") * environment_weights.x \
		+ Color("#18213b") * environment_weights.y + Color("#12273a") * environment_weights.z


func update_road_visibility(distance: float) -> void:
	assert(track_revision == simulation.track.revision, "The race course cannot change after preparation.")
	var ahead: float = 650 if int(settings.quality) == 1 else 960
	var first: int = maxi(-3, floori((distance - 144) / ROAD_CHUNK_LENGTH))
	var last: int = floori((distance + ahead) / ROAD_CHUNK_LENGTH)
	for index: int in cached_chunks:
		cached_chunks[index].visible = index >= first and index <= last


func build_road_chunk(index: int) -> void:
	assert(not level_ready and not cached_chunks.has(index), "Level geometry is built only before the race.")
	var start: float = index * ROAD_CHUNK_LENGTH
	var end: float = start + ROAD_CHUNK_LENGTH
	var chunk: Node3D = Node3D.new()
	chunk.name = "RoadChunk%d" % index
	chunk.set_meta("distance", start)
	chunk.visible = false
	road.add_child(chunk)
	road_chunks.append(chunk)
	cached_chunks[index] = chunk
	chunks_built += 1
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(road_material)
	for step: int in range(8):
		var a_distance: float = start + step * 6
		var b_distance: float = a_distance + 6
		var a_sample: Dictionary = simulation.track.presentation_sample(a_distance)
		var b_sample: Dictionary = simulation.track.presentation_sample(b_distance)
		var split: bool = not a_sample.split.is_empty() or not b_sample.split.is_empty()
		for side: int in ([-1, 1] if split else [0]):
			add_road_strip(surface, a_distance, b_distance, side)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = surface.commit()
	chunk.add_child(mesh)
	var terrain_surface: SurfaceTool = SurfaceTool.new()
	terrain_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	terrain_surface.set_material(terrain_material)
	var offsets: Array[float] = [-260, -225, -190, -155, -120, -85, -60, -40, -25, -12,
		0, 12, 25, 40, 60, 85, 120, 155, 190, 225, 260]
	for step: int in range(4):
		var a_distance: float = start + step * 12
		var b_distance: float = a_distance + 12
		var a: Transform3D = simulation.track.frame(a_distance)
		var b: Transform3D = simulation.track.frame(b_distance)
		var a_sample: Dictionary = simulation.track.presentation_sample(a_distance)
		var b_sample: Dictionary = simulation.track.presentation_sample(b_distance)
		for band: int in range(offsets.size() - 1):
			var left: float = offsets[band]
			var right: float = offsets[band + 1]
			terrain_surface.set_uv(Vector2(1 if (index + band) % 4 == 0 else 0, 0))
			add_quad(terrain_surface,
				a * Vector3(left, terrain_height(left, a_distance, a_sample), 0),
				a * Vector3(right, terrain_height(right, a_distance, a_sample), 0),
				b * Vector3(right, terrain_height(right, b_distance, b_sample), 0),
				b * Vector3(left, terrain_height(left, b_distance, b_sample), 0))
	var terrain: MeshInstance3D = MeshInstance3D.new()
	terrain.mesh = terrain_surface.commit()
	chunk.add_child(terrain)
	var props: Node3D = Node3D.new()
	chunk.add_child(props)
	build_scenery(start, end, props)
	for stage_index: int in range(simulation.track.path.size()):
		var d: float = simulation.track.starts[stage_index]
		var label: String = "CHECKPOINT"
		if stage_index == 0:
			d = 12
			label = "NEON RACER"
		if d >= start and d < end:
			make_gantry(simulation.track.frame(d), label, d, props)
	if simulation.track.total_length >= start and simulation.track.total_length < end:
		make_gantry(simulation.track.frame(simulation.track.total_length), "FINISH", simulation.track.total_length, props)
	build_tunnels(start, end, props)


func add_road_strip(surface: SurfaceTool, start: float, end: float, side: int) -> void:
	var vertices: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var lane_data: Array[Vector2] = []
	for distance: float in [start, end]:
		var sample: Dictionary = simulation.track.presentation_sample(distance)
		var half_width: float = float(road_span(sample, side).y)
		var frame: Transform3D = simulation.track.branch_frame(distance, side) if side != 0 else simulation.track.frame(distance)
		var extent: float = maxf(half_width * 1.65, half_width + float(sample.shoulder) + 1.0)
		var lanes: float = float(sample.lanes)
		if side != 0 and not sample.split.is_empty():
			lanes = 3 if side < 0 else int(sample.split.narrow_count)
		for sign_value: float in [-1.0, 1.0]:
			vertices.append(frame.origin + frame.basis.x * extent * sign_value + Vector3.UP * 0.02)
			uvs.append(Vector2((sign_value * extent / half_width + 1) / 2, distance))
			lane_data.append(Vector2(lanes, side))
	for index: int in [0, 3, 1, 0, 2, 3]:
		surface.set_uv(uvs[index])
		surface.set_uv2(lane_data[index])
		surface.add_vertex(vertices[index])


func terrain_height(lateral: float, distance: float, sample: Dictionary) -> float:
	var width: float = float(sample.half_width)
	var apron: float = maxf(width + float(sample.shoulder) + 5, width * 1.72 + 2)
	var fade: float = smoothstep(apron, apron + 58, absf(lateral))
	var floor_height: float = -0.58
	if not sample.split.is_empty():
		floor_height += minf(float(sample.split.left_elevation), float(sample.split.right_elevation))
	return floor_height + (sin(distance * 0.014 + lateral * 0.018) * 8
		+ sin(distance * 0.008 - lateral * 0.026) * 12) * fade


func road_span(sample: Dictionary, side: int) -> Vector3:
	if side == 0 or sample.split.is_empty():
		return Vector3(0, float(sample.half_width), 0)
	var cross: Dictionary = sample.split
	return Vector3(float(cross.left_center if side < 0 else cross.right_center),
		float(cross.left_half if side < 0 else cross.right_half),
		float(cross.left_elevation if side < 0 else cross.right_elevation))


func build_tunnels(start: float, end: float, parent: Node3D) -> void:
	for index: int in range(simulation.track.path.size()):
		var id: String = simulation.track.path[index]
		if id not in ["city-axis-tunnel", "skyline-2"]:
			continue
		var length: float = float(simulation.track.sections[id].length)
		if length < 240:
			continue
		var half_width: float = float(simulation.track.sample(id, 120).half_width)
		for distance: int in range(120, int(length) - 120, 14):
			var run_distance: float = simulation.track.starts[index] + distance
			if run_distance < start or run_distance >= end:
				continue
			var frame: Transform3D = simulation.track.frame(simulation.track.starts[index] + distance)
			var root: Node3D = Node3D.new()
			root.name = "TunnelSection%d" % run_distance
			root.set_meta("distance", simulation.track.starts[index] + distance)
			parent.add_child(root)
			root.transform = frame
			for side: float in [-1.0, 1.0]:
				box(root, Vector3(0.4, 5.2, 14.2), Vector3(side * (half_width + 0.5), 2.6, -7),
					paint(Color("#111927")))
				box(root, Vector3(0.05, 4.8, 0.1), Vector3(side * half_width, 2.4, 0), neon(coast_color))
			box(root, Vector3(half_width * 2 + 1.4, 0.4, 14.2), Vector3(0, 5.4, -7),
				paint(Color("#0c1020")))
			box(root, Vector3(half_width * 2, 0.05, 0.1), Vector3(0, 5.16, 0), neon(Color("#ff2d95")))


func build_scenery(start: float, end: float, parent: Node3D) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var spacing: int = 90 if int(settings.quality) == 1 else 55
	for i: int in range(maxi(0, ceili(start / spacing) * spacing), ceili(end), spacing):
		rng.seed = 455 + i
		var frame: Transform3D = simulation.track.frame(i)
		var sample: Dictionary = simulation.track.at_distance(i)
		var environment_id: String = str(sample.environment)
		for side: float in [-1.0, 1.0]:
			if environment_id == "sunset-coast":
				var palm: Node3D = Node3D.new()
				palm.set_meta("distance", i)
				parent.add_child(palm)
				palm.transform = frame.translated_local(Vector3(side * rng.randf_range(12, 30), -1, 0))
				box(palm, Vector3(0.22, 8, 0.22), Vector3(0, 4, 0), neon(Color("#50256c")))
				for leaf: int in range(7):
					var frond: MeshInstance3D = box(palm, Vector3(4.5, 0.05, 0.25),
						Vector3.ZERO, neon(coast_color))
					frond.position = Vector3(cos(leaf * TAU / 7), 8, sin(leaf * TAU / 7)) * Vector3(2, 1, 2)
					frond.rotation = Vector3(0, -leaf * TAU / 7, -0.15)
				var h: float = rng.randf_range(20, 75)
				make_building(frame.translated_local(Vector3(side * rng.randf_range(85, 170), 0, 0)),
					Vector3(14, h, 20), absi(i + side) % facade_materials.size(), i, parent)
			elif environment_id in ["neon-city", "violet-skyway"]:
				var h: float = rng.randf_range(12, 65)
				var variant: int = absi(int(i / spacing) + side) % facade_materials.size()
				make_building(frame.translated_local(Vector3(side * rng.randf_range(26, 65), 0, 0)),
					Vector3(rng.randf_range(14, 22), h, 22), variant, i, parent)
				if int(settings.quality) != 1:
					make_building(frame.translated_local(Vector3(side * rng.randf_range(95, 160), 0, -20)),
						Vector3(24, rng.randf_range(55, 120), 28), (variant + 2) % facade_materials.size(), i, parent)
			else:
				var mountain: MeshInstance3D = MeshInstance3D.new()
				mountain.set_meta("distance", i)
				var cone: CylinderMesh = CylinderMesh.new()
				cone.top_radius = 0
				cone.bottom_radius = rng.randf_range(35, 80)
				cone.height = rng.randf_range(35, 100)
				cone.radial_segments = 5
				mountain.mesh = cone
				mountain.material_override = paint(Color("#14213b"))
				parent.add_child(mountain)
				mountain.transform = frame.translated_local(Vector3(side * rng.randf_range(70, 150), 0, 0))
		if i % (spacing * 3) == 0:
			make_sign(frame.translated_local(Vector3(10, 0, 0)),
				["VANTA", "EYE-NET", "SUMMIT", "ORBIT"][int(i / spacing) % 4], i, parent)
			if environment_id in ["sunset-coast", "neon-city", "violet-skyway"]:
				make_sky_traffic(frame, i, parent)


func make_building(frame: Transform3D, dimensions: Vector3, variant: int, distance: int, parent: Node3D) -> void:
	var building: Node3D = Node3D.new()
	building.name = "NeonBuilding%d_%d" % [distance, parent.get_child_count()]
	building.set_meta("distance", distance)
	parent.add_child(building)
	building.transform = frame
	var facade: MeshInstance3D = box(building, dimensions, Vector3(0, dimensions.y / 2, 0), facade_materials[variant])
	facade.name = "EmissiveFacade"
	var color: Color = facade_materials[variant].get_shader_parameter("accent")
	var trim: StandardMaterial3D = neon(color)
	for side: int in [-1, 1]:
		box(building, Vector3(0.12, dimensions.y, 0.12),
			Vector3(side * dimensions.x / 2, dimensions.y / 2, dimensions.z / 2 + 0.05), trim)
	for fraction: float in [0.33, 0.66, 1.0]:
		box(building, Vector3(dimensions.x + 0.12, 0.12, dimensions.z + 0.12),
			Vector3(0, dimensions.y * fraction, 0), trim)
	if dimensions.y > 25:
		var sign: MeshInstance3D = MeshInstance3D.new()
		sign.name = "AnimatedBillboard"
		var panel: QuadMesh = QuadMesh.new()
		panel.size = Vector2(dimensions.x * 0.8, minf(7, dimensions.y * 0.2))
		sign.mesh = panel
		sign.material_override = display_materials[variant]
		sign.position = Vector3(0, dimensions.y * 0.72, dimensions.z / 2 + 0.15)
		building.add_child(sign)
		var title: Label3D = Label3D.new()
		title.text = ["VANTA // NET", "NIGHT MARKET", "ORBIT SYSTEMS", "NEON DISTRICT", "EYE-NET", "AFTER HOURS"][variant]
		title.font_size = 48
		title.pixel_size = 0.025
		title.position = sign.position + Vector3(0, 0, 0.05)
		title.modulate = Color("#fff4fb")
		building.add_child(title)
	if dimensions.y > 65 and variant % 2 == 0 and int(settings.quality) != 1:
		var beam: MeshInstance3D = MeshInstance3D.new()
		beam.name = "RooftopSearchlight"
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 12
		cone.bottom_radius = 0.2
		cone.height = 90
		cone.radial_segments = 12
		beam.mesh = cone
		var light: StandardMaterial3D = neon(color)
		light.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		light.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		light.albedo_color = Color(color, 0.035)
		light.emission_energy_multiplier = 0.4
		beam.material_override = light
		beam.position = Vector3(0, dimensions.y, 0)
		# Offset the cone above its pivot so it sweeps from the rooftop.
		var beam_root: Node3D = Node3D.new()
		building.add_child(beam_root)
		beam_root.position = beam.position
		beam.position = Vector3(0, 45, 0)
		beam_root.add_child(beam)
		beam_root.set_meta("home", beam_root.transform)
		beam_root.set_meta("phase", distance * 0.03 + variant)
		beam_root.set_meta("beam", true)
		ambient_nodes.append(beam_root)


func make_sky_traffic(frame: Transform3D, distance: int, parent: Node3D) -> void:
	for side: int in [-1, 1]:
		var drone: Node3D = Node3D.new()
		drone.name = "SkyTraffic%d_%d" % [distance, side]
		parent.add_child(drone)
		drone.transform = frame.translated_local(Vector3(side * 75, 16 + distance % 19, 0))
		box(drone, Vector3(2.4, 0.7, 5), Vector3.ZERO, paint(Color("#10132c")))
		for edge: int in [-1, 1]:
			box(drone, Vector3(0.15, 0.15, 7), Vector3(edge * 1.3, 0, 2),
				neon(coast_color if side < 0 else Color("#ff2d95")))
		box(drone, Vector3(2.5, 0.12, 0.15), Vector3(0, -0.2, -2.5), neon(Color("#ffe45e")))
		drone.set_meta("home", drone.transform)
		drone.set_meta("phase", distance * 0.07 + side)
		ambient_nodes.append(drone)


func update_background() -> void:
	for material: ShaderMaterial in facade_materials + display_materials:
		material.set_shader_parameter("animation_time", time)
	var motion: float = 0 if bool(settings.reduce_motion) or bool(settings.reduce_flashes) else 1
	for node: Node3D in ambient_nodes:
		if not node.is_visible_in_tree():
			continue
		var home: Transform3D = node.get_meta("home")
		var phase: float = float(node.get_meta("phase"))
		if bool(node.get_meta("beam", false)):
			node.transform = home.rotated_local(Vector3.FORWARD, sin(time * 0.18 + phase) * 0.35 * motion)
		else:
			node.transform = home.translated_local(Vector3(sin(time * 0.22 + phase) * 8,
				sin(time * 1.2 + phase) * 0.6, sin(time * 0.1 + phase) * 60) * motion)


func update_actors() -> void:
	assert(simulation.traffic.size() <= traffic_nodes.size(), "Traffic must fit the prepared actor pool.")
	assert(simulation.obstacles.size() <= obstacle_nodes.size(), "Obstacles must fit the prepared actor pool.")
	for i: int in range(traffic_nodes.size()):
		traffic_nodes[i].visible = i < simulation.traffic.size()
		if i < simulation.traffic.size():
			var state: Dictionary = simulation.traffic[i]
			traffic_nodes[i].transform = simulation.track.actor_frame(float(state.distance), float(state.lateral))
			traffic_nodes[i].update_effects(0, float(state.speed), false, bool(state.hit), 0, time,
				bool(settings.reduce_motion), bool(settings.reduce_flashes))
	for i: int in range(obstacle_nodes.size()):
		obstacle_nodes[i].visible = i < simulation.obstacles.size()
		if i < simulation.obstacles.size():
			var state: Dictionary = simulation.obstacles[i]
			obstacle_nodes[i].transform = simulation.track.actor_frame(float(state.distance), float(state.lateral))


static func add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var vertices: Array[Vector3] = [a, c, b, a, d, c]
	for i: int in range(vertices.size()):
		tool.set_color([Color.RED, Color.GREEN, Color.BLUE][i % 3])
		tool.add_vertex(vertices[i])


static func paint(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.4
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func neon(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = paint(color)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	return material


static func box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = position
	parent.add_child(node)
	return node


static func make_car(color: Color, accent: Color, trails: bool = false) -> RacerCar:
	return RacerCar.new(color, accent, trails)


func make_sign(frame: Transform3D, text: String, distance: float, parent: Node3D) -> void:
	var root: Node3D = Node3D.new()
	root.set_meta("distance", distance)
	parent.add_child(root)
	root.transform = frame
	box(root, Vector3(0.1, 8, 0.1), Vector3(0, 4, 0), paint(Color("#34445c")))
	box(root, Vector3(6, 2, 0.1), Vector3(0, 8, 0), neon(Color("#501e6a")))
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = 80
	label.pixel_size = 0.012
	label.position = Vector3(0, 8, 0.08)
	label.modulate = coast_color
	root.add_child(label)


func make_gantry(frame: Transform3D, text: String, distance: float, parent: Node3D) -> void:
	var root: Node3D = Node3D.new()
	root.set_meta("distance", distance)
	parent.add_child(root)
	root.transform = frame
	for side: float in [-1.0, 1.0]:
		box(root, Vector3(0.15, 6, 0.15), Vector3(side * 7, 3, 0), neon(coast_color))
	box(root, Vector3(14, 0.2, 0.15), Vector3(0, 6, 0), neon(Color("#ff2d95")))
	var label: Label3D = Label3D.new()
	label.text = text
	label.position = Vector3(0, 5.2, 0.1)
	label.font_size = 80
	label.pixel_size = 0.012
	root.add_child(label)

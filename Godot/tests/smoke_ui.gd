extends SceneTree

var failures: int = 0


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var app: Node = preload("res://scenes/main.tscn").instantiate()
	app.store = RacerProfileStore.new("user://test-ui-profile-%d.json" % OS.get_process_id())
	app.recovery_path = app.store.save_path + ".run"
	app.store.profile.tutorial = true
	root.add_child(app)
	app.audio.initialize_bank()
	await process_frame
	check(app.audio.stems.size() == 5 and app.audio.engines.size() == 3, "Procedural sound bank loads")
	check(app.state == "menu", "Main menu opens")
	await check_title_spacing(app)
	app.show_garage()
	await process_frame
	check(app.state == "garage", "Garage opens")
	app.show_customization()
	await process_frame
	check(app.state == "customization", "Customization opens")
	app.show_settings()
	await process_frame
	check(app.state == "settings", "Settings opens")
	app.show_accessibility()
	await process_frame
	check(app.state == "accessibility", "Accessibility opens")
	app.show_course()
	await process_frame
	check(app.state == "course", "Race setup opens course selection before loading")
	check(press_button(app, "PEAKS STORM SWITCHBACK"), "Course setup exposes the peaks choice")
	check(app.course_choices.has("peaks-storm-switchback"), "Pre-race course choice updates the itinerary")
	check(press_button(app, "CITY AXIS TUNNEL"), "Course setup can switch back to the tunnel")
	app.start_race()
	check(app.state == "loading" and not app.world.level_ready, "Race waits for full level preparation")
	while app.state == "loading":
		check(app.simulation.countdown == 3 and app.simulation.elapsed == 0, "Preparation never consumes countdown or race time")
		await process_frame
	await process_frame
	check(app.world != null and app.hud != null and app.controls != null, "Race renderer, HUD and controls exist")
	app.simulation.phase = "racing"
	app.simulation.speed = 100
	app.audio._process(0.1)
	check(app.audio.engines[0].volume_db > -80, "Vehicle sound follows race state")
	app.store.profile.settings.mute_effects = true
	app.audio._process(0.1)
	check(app.audio.engines[0].volume_db == -80, "Effects mute silences vehicle layers")
	app.store.profile.settings.mute_effects = false
	check(app.controls.size.x > 500 and app.controls.size.y > 200, "Race controls fill viewport")
	check_road_geometry(app)
	check_wipeout_pose(app)
	check_neon_effects(app)
	check_cyberpunk_scenery(app)
	for route: String in ["skyline-run", "void-causeway", "neon-loop"]:
		app.store.profile.route = route
		await app.start_race()
		await process_frame
		check_road_geometry(app, "coast-solar-sweep" if route == "neon-loop" else "skyline-1")
	await check_prepared_courses(app)
	await app.start_race()
	await process_frame
	await check_window_scaling(app)
	var left_touch: InputEventScreenTouch = InputEventScreenTouch.new()
	left_touch.index = 0
	left_touch.position = app.controls.global_position + app.controls.steering_rect().position + Vector2(30, 30)
	left_touch.pressed = true
	app.controls._input(left_touch)
	var boost_touch: InputEventScreenTouch = InputEventScreenTouch.new()
	boost_touch.index = 1
	boost_touch.position = app.controls.global_position + app.controls.action_center("boost")
	boost_touch.pressed = true
	app.controls._input(boost_touch)
	check(app.controls.steering < 0 and app.controls.boost, "Multi-touch steering and boost are independent")
	boost_touch.pressed = false
	app.controls._input(boost_touch)
	check(app.controls.steering < 0 and not app.controls.boost, "Releasing boost keeps steering")
	app.show_pause()
	check(app.simulation.phase == "paused" and app.controls.steering == 0, "Pause clears held touch input")
	var recovery: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(app.recovery_path))
	check(recovery.course == app.simulation.track.path, "Interrupted runs preserve the preselected course")
	# Remove the test recovery marker created by pause, before leaving the test scene.
	check(app.clear_recovery(), "Test recovery marker removed")
	app.simulation.phase = "finished"
	app.show_results(true)
	await process_frame
	check(app.state == "results", "Results opens")
	app.show_menu()
	await process_frame
	check(app.world == null and app.simulation == null, "Title releases race state")
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	var test_path: String = "user://test-ui-profile-%d.json" % OS.get_process_id()
	if FileAccess.file_exists(test_path):
		check(DirAccess.remove_absolute(test_path) == OK, "Temporary UI profile cleaned up")
	print("Godot UI smoke: %d failures" % failures)
	quit(1 if failures else 0)


func check_title_spacing(app: Node) -> void:
	var original: Vector2i = root.size
	for dimensions: Vector2i in [original, Vector2i(1600, 900)]:
		root.size = dimensions
		await process_frame
		await process_frame
		for node: Node in app.safe_ui.find_children("*", "Button", true, false):
			if node.text == "RACE":
				var panel: Control = node.get_parent().get_parent()
				var gap: float = app.safe_ui.get_global_rect().end.y - panel.get_global_rect().end.y
				check(absf(gap - root.get_visible_rect().size.y * 0.05) < 1,
					"Title buttons sit five percent above the bottom at each window size")
	root.size = original
	await process_frame
	await process_frame


func press_button(app: Node, text: String) -> bool:
	for node: Node in app.safe_ui.find_children("*", "Button", true, false):
		if node.text == text:
			node.pressed.emit()
			return true
	return false


func check_cyberpunk_scenery(app: Node) -> void:
	var world: RacerWorld = app.world
	check(world.road.find_children("EmissiveFacade", "MeshInstance3D", true, false).size() > 100,
		"The full course has emissive cyberpunk facades rather than plain box buildings")
	check(world.road.find_children("AnimatedBillboard", "MeshInstance3D", true, false).size() > 50,
		"Neon billboards are prepared throughout the city and skyline")
	check(not world.road.find_children("RooftopSearchlight", "MeshInstance3D", true, false).is_empty(),
		"Rooftop searchlight geometry is prepared before racing")
	check(world.ambient_nodes.size() > 20, "Flying background traffic and searchlights are prebuilt")
	world.update_road_visibility(0)
	world._process(0)
	var actor: Node3D = world.ambient_nodes[0]
	var before: Transform3D = actor.transform
	world._process(1)
	check(not actor.transform.is_equal_approx(before), "Background traffic moves without constructing new nodes")
	app.simulation.set_paused(true)
	before = actor.transform
	var clock: float = world.time
	world._process(1)
	check(actor.transform.is_equal_approx(before) and world.time == clock, "Pausing freezes background motion and shader clocks")
	app.simulation.set_paused(false)
	world.settings.reduce_motion = true
	world.apply_settings()
	world._process(1)
	var home: Transform3D = actor.get_meta("home")
	check(actor.transform.is_equal_approx(home), "Reduced motion makes background traffic and searchlights static")
	for material: ShaderMaterial in world.facade_materials + world.display_materials:
		check(float(material.get_shader_parameter("motion_strength")) == 0, "Reduced motion disables moving facade and billboard patterns")
	world.settings.reduce_flashes = true
	world.apply_settings()
	for material: ShaderMaterial in world.facade_materials + world.display_materials:
		check(float(material.get_shader_parameter("pulse_strength")) == 0, "Reduced flashes disables animated neon brightness")
	world.settings.reduce_motion = false
	world.settings.reduce_flashes = false
	world.apply_settings()


func check_road_geometry(app: Node, split_id: String = "coast-solar-sweep") -> void:
	var track: RacerTrack = app.simulation.track
	if track.sections.has(split_id):
		var start: float = track.starts[track.path.find(split_id)]
		for side: int in [-1, 1]:
			for fraction: float in [0.215, 0.285, 0.5, 0.755, 0.815]:
				var distance: float = start + float(track.sections[split_id].length) * fraction
				var tool: SurfaceTool = SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				app.world.add_road_strip(tool, distance, distance + 6, side)
				var mesh: ArrayMesh = tool.commit()
				var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var frame: Transform3D = track.branch_frame(distance, side)
				check(((vertices[0] + vertices[2]) / 2).distance_to(frame.origin + Vector3.UP * 0.02) < 0.0001,
					"Rendered split road is centered on the vehicle frame")
				check((vertices[2] - vertices[0]).normalized().dot(frame.basis.x) > 0.99999,
					"Rendered split road uses the branch tangent, not the aggregate tangent")
				var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
				check(uvs[0].x < 0 and uvs[2].x > 1 and absf(uvs[0].y - distance) < 0.001,
					"Road markings follow road-local UVs and preserve visible shoulders")
	app.world.update_road_visibility(0)
	var visible_count: int = 0
	for chunk: Node3D in app.world.road_chunks:
		visible_count += 1 if chunk.visible else 0
	check(visible_count < 30 and visible_count > 10, "Only nearby road/terrain chunks render")
	var middle: float = track.total_length / 2
	app.world.update_road_visibility(middle)
	for chunk: Node3D in app.world.road_chunks:
		var distance: float = float(chunk.get_meta("distance"))
		if distance <= middle and distance + RacerWorld.ROAD_CHUNK_LENGTH >= middle:
			check(chunk.visible, "Moving down the route activates the road under the car")
	for index: int in range(track.path.size()):
		var id: String = track.path[index]
		for fraction: float in [0.2, 0.5, 0.8]:
			var distance: float = track.starts[index] + float(track.sections[id].length) * fraction
			var sample: Dictionary = track.at_distance(distance)
			app.world.update_road_visibility(distance)
			for side: int in ([0] if sample.split.is_empty() else [-1, 1]):
				var frame: Transform3D = track.branch_frame(distance, side) if side != 0 else track.frame(distance)
				check(terrain_clears_road(app.world, frame.origin),
					"Terrain does not cover the road: %s / %.1f / %d" % [id, fraction, side])
	app.world.update_road_visibility(0)


func terrain_clears_road(world: RacerWorld, point: Vector3) -> bool:
	for chunk: Node3D in world.road_chunks:
		if not chunk.visible:
			continue
		var terrain: MeshInstance3D = chunk.get_child(1)
		var bounds: AABB = terrain.mesh.get_aabb()
		if point.x < bounds.position.x or point.x > bounds.end.x or point.z < bounds.position.z or point.z > bounds.end.z:
			continue
		var vertices: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i: int in range(0, vertices.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(point + Vector3.UP * 64, Vector3.DOWN,
				vertices[i], vertices[i + 1], vertices[i + 2])
			if hit != null and hit.y > point.y + 0.04:
				return false
	return true


func check_wipeout_pose(app: Node) -> void:
	var sim: RacerSimulation = app.simulation
	sim.crash(0.75, -0.2)
	sim.wipeout = sim.wipeout_duration - 0.45
	var frame: Transform3D = sim.track.actor_frame(sim.distance, sim.lateral, sim.split_side)
	var pose: Transform3D = app.world.wipeout_transform(frame)
	var pivot: Vector3 = Vector3(0, float(app.world.hero.get_meta("center_height")), 0)
	check((pose * pivot).y > (frame * pivot).y + 1.5, "Crash launches the car above the road")
	check(pose.basis.z.dot(frame.basis.z) < 0.9, "Airborne crash combines spin and roll")
	app.world.settings.reduce_motion = true
	pose = app.world.wipeout_transform(frame)
	check(pose.basis.is_equal_approx(frame.basis), "Reduced motion disables crash spin and roll")
	check((pose * pivot).y < (frame * pivot).y + 0.36, "Reduced motion limits launch height")
	app.world.settings.reduce_motion = false
	sim.wipeout = 0
	sim.wipeout_duration = 0
	sim.wipeout_direction = 0
	sim.wipeout_severity = 0
	sim.lateral = 0


func check_neon_effects(app: Node) -> void:
	var car: RacerCar = app.world.hero
	check(car.flames.size() == 2 and car.trails.size() == 2, "Hero has twin exhausts and world-space neon trails")
	check(car.body_root.find_children("*Canopy*", "MeshInstance3D", false, false).size() == 6,
		"Native canopy contour lighting is present")
	check(car.body_root.find_children("*Shoulder*", "MeshInstance3D", false, false).size() == 4,
		"Native shoulder contour lighting is present")
	car.update_effects(0, 110, false, false, 0, 1, false, false)
	var resting_length: float = car.flames[0].scale.y
	var resting_light: float = car.glow.light_energy
	var resting_trim: float = car.trim_materials[0].emission_energy_multiplier
	car.update_effects(0.7, 144, true, true, 0.3, 1, false, false)
	check(car.flames[0].scale.y > resting_length * 3, "Boost visibly extends the exhaust flames")
	check(car.glow.light_energy > resting_light and car.trim_materials[0].emission_energy_multiplier > resting_trim,
		"Boost brightens underglow and contour lights")
	check(car.tail_material.emission_energy_multiplier == 3 and car.trails[0].emitting, "Braking and boost trails respond to driving")
	check(not car.trails[0].local_coords, "Boost trails stay in world space as the car moves")
	car.set_effects_paused(true)
	check(car.trails[0].speed_scale == 0, "Pausing freezes live particle effects")
	car.set_effects_paused(false)
	car.update_effects(0.7, 144, true, false, 0.3, 1, true, true)
	check(car.animated.rotation == Vector3.ZERO and car.animated.position.y == 0,
		"Reduced motion removes vehicle lean and hover bob")
	check(not car.trails[0].emitting, "Reduced effects disable moving boost trails")
	var strength: float = float(car.flame_material.get_shader_parameter("strength"))
	car.update_effects(0.7, 144, true, false, 0.3, 2, true, true)
	check(float(car.flame_material.get_shader_parameter("strength")) == strength, "Reduced flashes disables exhaust pulsing")
	car.update_effects(0, 100, false, false, 0, 0, false, false)


func check_prepared_courses(app: Node) -> void:
	for destination: String in ["city-axis-tunnel", "peaks-storm-switchback"]:
		app.course_choices.assign([destination])
		await app.start_race()
		app.state = "capture"
		var sim: RacerSimulation = app.simulation
		var world: RacerWorld = app.world
		sim.phase = "racing"
		sim.traffic_enabled = false
		var built: int = world.chunks_built
		var node_count: int = get_node_count()
		var ids: Dictionary[int, int] = {}
		for index: int in world.cached_chunks:
			ids[index] = world.cached_chunks[index].get_instance_id()
		check(world.level_ready and built == ceili((sim.track.total_length + RacerWorld.FINISH_EXTENSION) / RacerWorld.ROAD_CHUNK_LENGTH) + 4,
			"The entire course and finish extension exist before the countdown")
		check(world.traffic_nodes.size() == RacerSimulation.MAX_TRAFFIC and world.obstacle_nodes.size() == RacerSimulation.MAX_OBSTACLES,
			"Traffic and obstacle renderers are prepared before racing")
		var tunnels: Array[Node] = world.road.find_children("TunnelSection*", "Node3D", true, false)
		check(not tunnels.is_empty() if destination == "city-axis-tunnel" else tunnels.is_empty(),
			"Tunnel geometry matches the course selected before racing")
		var revision: int = sim.track.revision
		for index: int in range(sim.track.path.size() - 1):
			sim.stage_id = sim.track.path[index]
			sim.stage_start = sim.track.starts[index]
			sim.committed.assign(sim.track.path.slice(1, index + 1))
			sim.distance = sim.stage_start + float(sim.track.sections[sim.stage_id].length) - 0.5
			sim.previous_distance = sim.distance
			sim.lateral = 0.35 if destination == "city-axis-tunnel" else -0.35
			sim.previous_lateral = sim.lateral
			sim.speed = 110
			world._process(1.0 / 60)
			if sim.stage_id == "city-fork" and not tunnels.is_empty():
				check(tunnels[0].is_visible_in_tree(), "The tunnel is already visible approaching its checkpoint")
			sim.advance(1.0 / 60, 0, 1, 0, false)
			world._process(1.0 / 60)
			check(sim.stage_id == sim.track.path[index + 1] and sim.phase == "racing",
				"Every checkpoint advances along the prepared course")
			check(world.chunks_built == built and get_node_count() == node_count and sim.track.revision == revision,
				"No level nodes or meshes are built, freed, or replaced during racing")
			if sim.stage_id == "city-axis-tunnel":
				check(tunnels[0].is_visible_in_tree(), "Crossing the checkpoint preserves the visible tunnel")
		for distance: float in [0.0, sim.track.total_length / 2, sim.track.total_length + 900]:
			world.update_road_visibility(distance)
			check(world.cached_chunks.has(floori(distance / RacerWorld.ROAD_CHUNK_LENGTH)),
				"Road geometry is already resident anywhere in the level")
		for index: int in ids:
			check(world.cached_chunks[index].get_instance_id() == ids[index], "Every prepared chunk retains its identity")
		var actor_ids: PackedInt64Array = []
		for actor: Node3D in world.actors.get_children():
			actor_ids.append(actor.get_instance_id())
		for index: int in range(RacerSimulation.MAX_TRAFFIC):
			sim.traffic.append({"distance": sim.distance + index * 10, "lateral": 0, "speed": 80, "hit": false})
		for index: int in range(RacerSimulation.MAX_OBSTACLES):
			sim.obstacles.append({"distance": sim.distance + index * 20, "lateral": 0, "hit": false})
		world.update_actors()
		check(world.actors.get_child_count() == actor_ids.size() and get_node_count() == node_count,
			"Filling the traffic and obstacle pools creates no new scene nodes")
		for index: int in range(actor_ids.size()):
			check(world.actors.get_child(index).get_instance_id() == actor_ids[index], "Actor pools retain their pre-race instances")
		sim.traffic.clear()
		sim.obstacles.clear()
		check_checkpoint_presentation(app)


func check_checkpoint_presentation(app: Node) -> void:
	var sim: RacerSimulation = app.simulation
	var world: RacerWorld = app.world
	sim.phase = "racing"
	sim.traffic_enabled = false
	sim.speed = 110
	sim.stage_id = sim.track.start_id
	sim.stage_start = 0
	sim.committed.clear()
	sim.distance = float(sim.track.sections[sim.stage_id].length) - 0.5
	sim.previous_distance = sim.distance
	world.update_road_visibility(sim.distance)
	world._process(1.0 / 60)
	var index: int = floori(sim.distance / RacerWorld.ROAD_CHUNK_LENGTH)
	var chunk_id: int = world.cached_chunks[index].get_instance_id()
	var revision: int = sim.track.revision
	var camera: Transform3D = world.camera.transform
	sim.advance(1.0 / 60, 0, 1, 0, false)
	world._process(1.0 / 60)
	check(sim.committed.size() == 1 and sim.phase == "racing", "Driving crosses a checkpoint without pausing")
	check(sim.track.revision == revision, "Ordinary checkpoint does not rebuild the track")
	check(world.cached_chunks[index].get_instance_id() == chunk_id, "Checkpoint reuses the actual mesh under the car")
	check(world.camera.position.distance_to(camera.origin) < 4, "Checkpoint camera position stays continuous")
	check(world.camera.basis.z.distance_to(camera.basis.z) < 0.03, "Checkpoint grade changes do not snap the camera")
	world.environment_weights = Vector3(1, 0, 0)
	world.environment_target = Vector3(1, 0, 0)
	world.update_environment("neon-city", 1.0 / 60)
	check(world.environment_weights.x > 0.99 and world.sun.visible, "Environment transition starts without hiding the sun abruptly")
	world.update_environment("neon-city", 1.5)
	check(world.environment_weights.x > 0.1 and world.environment_weights.x < 0.9, "Checkpoint atmosphere blends gradually")
	world.update_environment("neon-city", 1.5)
	check(world.environment_weights.y == 1 and not world.sun.visible, "Environment blend reaches its new theme")


func check_window_scaling(app: Node) -> void:
	check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Window scales the canvas without letterboxing")
	var original: Vector2i = root.size
	for dimensions: Vector2i in [Vector2i(900, 600), Vector2i(1800, 700), Vector2i(700, 900)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var viewport: Vector2 = root.get_visible_rect().size
		check(app.ui.size.distance_to(viewport) < 1 and app.screen.size.distance_to(viewport) < 1,
			"Game UI fills the resized window: " + str(dimensions))
		check(app.hud.size.distance_to(viewport) < 1 and app.controls.size.distance_to(viewport) < 1,
			"HUD and driving controls follow the viewport")
		check(app.hud.get_rect().has_point(app.pause_button.position + app.pause_button.size / 2),
			"Pause remains inside the resized HUD")
		for action: String in ["brake", "boost", "throttle"]:
			var center: Vector2 = app.controls.action_center(action)
			check(app.controls.get_rect().has_point(center) and app.controls.hit(center) == action,
				"Scaled controls retain accurate hit targets")
	root.size = original
	await process_frame
	await process_frame

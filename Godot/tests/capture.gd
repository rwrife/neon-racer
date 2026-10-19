extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func capture(name: String, directory: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(directory.path_join(name + ".png"))
	if error != OK:
		push_error("Capture failed: " + error_string(error))
		quit(1)


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Use a graphical Godot session and pass an existing output directory after --")
		quit(1)
		return
	var output: String = args[0]
	var app: Node = preload("res://scenes/main.tscn").instantiate()
	app.store = RacerProfileStore.new("user://capture-profile-%d.json" % OS.get_process_id())
	app.recovery_path = app.store.save_path + ".run"
	app.store.profile.tutorial = true
	root.add_child(app)
	await capture("01-title", output)
	app.show_garage()
	await capture("02-garage", output)
	app.show_settings()
	await capture("03-settings", output)
	app.show_course()
	await capture("18-course-selection", output)
	await app.start_race()
	app.state = "capture"
	app.simulation.phase = "racing"
	app.simulation.countdown = 0
	app.simulation.speed = 110
	app.simulation.distance = 150
	app.simulation.previous_distance = 150
	await capture("04-race", output)
	app.simulation.boosting = true
	app.simulation.speed = 144
	await create_timer(0.45).timeout
	await capture("12-neon-boost", output)
	app.simulation.boosting = false
	app.simulation.speed = 110
	await create_timer(0.4).timeout
	place(app, "coast-solar-sweep", 525, -1)
	await capture("06-split-left", output)
	place(app, "coast-solar-sweep", 525, 1)
	await capture("07-split-right", output)
	place(app, "city-axis-tunnel", 350)
	await capture("08-tunnel", output)
	place(app, "city-vanta-canyon", 350)
	app.world.update_environment("neon-city", 3)
	await create_timer(0.8).timeout
	await capture("19-cyberpunk-city", output)
	var original: Vector2i = root.size
	root.size = Vector2i(1800, 700)
	await capture("20-wide-window", output)
	root.size = Vector2i(900, 900)
	await capture("21-square-window", output)
	root.size = original
	await capture_checkpoint(app, output)
	await capture_course_checkpoint(app, output)
	place(app, app.simulation.track.start_id, 150)
	app.simulation.traffic_enabled = false
	app.simulation.crash(0.75, -0.2)
	for i: int in range(22):
		app.simulation.advance(1.0 / 60, 0, 1, 0, false)
	await capture("09-crash-airborne", output)
	for i: int in range(58):
		app.simulation.advance(1.0 / 60, 0, 1, 0, false)
	await capture("10-crash-landing", output)
	for i: int in range(50):
		app.simulation.advance(1.0 / 60, 0, 0, 0, false)
	await capture("11-crash-respawn", output)
	app.show_pause()
	await capture("05-pause", output)
	app.clear_recovery()
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	quit()


func capture_checkpoint(app: Node, output: String) -> void:
	var sim: RacerSimulation = app.simulation
	sim.traffic_enabled = false
	var track: RacerTrack = sim.track
	var source: String = ""
	for index: int in range(1, track.path.size()):
		if track.sections[track.path[index]].environment != track.sections[track.path[index - 1]].environment:
			source = track.path[index - 1]
			break
	assert(not source.is_empty(), "Capture route must include an environment transition.")
	place(app, source, float(track.sections[source].length) - 0.5)
	app.world.update_environment(str(track.sections[source].environment), 3)
	sim.speed = 110
	await capture("13-checkpoint-before", output)
	var maximum_update_ms: float = 0
	for i: int in range(120):
		var start: int = Time.get_ticks_usec()
		sim.advance(1.0 / 60, 0, 1, 0, false)
		app.world.update_road_visibility(sim.distance)
		maximum_update_ms = maxf(maximum_update_ms, (Time.get_ticks_usec() - start) / 1000.0)
		await process_frame
		if i == 0:
			await capture("14-checkpoint-crossing", output)
	await create_timer(1.5).timeout
	await capture("15-checkpoint-blended", output)
	print("Checkpoint crossing maximum simulation/visibility update: %.2f ms" % maximum_update_ms)


func capture_course_checkpoint(app: Node, output: String) -> void:
	var sim: RacerSimulation = app.simulation
	place(app, "city-fork", float(sim.track.sections["city-fork"].length) - 0.5)
	sim.lateral = 0.35
	sim.previous_lateral = sim.lateral
	sim.speed = 110
	var start: int = Time.get_ticks_usec()
	sim.advance(1.0 / 60, 0, 1, 0, false)
	app.world.update_road_visibility(sim.distance)
	print("Locked course checkpoint simulation/visibility update: %.2f ms" % ((Time.get_ticks_usec() - start) / 1000.0))
	assert(sim.stage_id == "city-axis-tunnel", "Steering cannot replace the tunnel course.")
	await capture("16-course-checkpoint", output)
	for i: int in range(16):
		await process_frame
	await capture("17-course-unchanged", output)


func place(app: Node, stage_id: String, distance: float, side: int = 0) -> void:
	var sim: RacerSimulation = app.simulation
	var index: int = sim.track.path.find(stage_id)
	assert(index >= 0, "Capture stage is not on the current route.")
	sim.stage_id = stage_id
	sim.committed.assign(sim.track.path.slice(1, index + 1))
	sim.stage_start = sim.track.starts[index]
	sim.distance = sim.stage_start + distance
	sim.previous_distance = sim.distance
	sim.split_side = side
	var cross: Dictionary = sim.track.split_cross(stage_id, distance)
	sim.lateral = (float(cross.left_center if side < 0 else cross.right_center) / float(cross.half_width)
		if not cross.is_empty() and side != 0 else 0.0)
	sim.previous_lateral = sim.lateral
	app.world.update_road_visibility(sim.distance)

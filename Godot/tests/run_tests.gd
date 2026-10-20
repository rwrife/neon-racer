extends SceneTree

var failures: int = 0
var checks: int = 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func close(actual: float, expected: float, description: String, tolerance: float = 0.000001) -> void:
	check(absf(actual - expected) <= tolerance,
		"%s: expected %.9f, got %.9f" % [description, expected, actual])


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/swift-reference.json"))
	var native_track: RacerTrack = RacerTrack.new()
	for fixture: Dictionary in reference.trackSamples:
		var sample: Dictionary = native_track.driving_sample(str(fixture.stage), float(fixture.distance), int(fixture.side))
		var name: String = "%s/%.2f/%d" % [fixture.stage, float(fixture.distance), int(fixture.side)]
		close(float(sample.curvature), float(fixture.curvature), name + " curvature")
		close(float(sample.grade), float(fixture.grade), name + " grade")
		close(float(sample.elevation), float(fixture.elevation), name + " elevation")
		close(float(sample.half_width), float(fixture.halfWidth), name + " width")
	for fixture: Dictionary in reference.driving:
		var sim: RacerSimulation = RacerSimulation.new("neon-loop", str(fixture.profile))
		sim.phase = "racing"
		sim.lateral = float(fixture.initialLateral)
		sim.speed = float(fixture.initialSpeed)
		sim.boosting = bool(fixture.boosting)
		var sample: Dictionary = {"curvature": fixture.curvature, "grade": fixture.grade,
			"half_width": 6.0, "shoulder": 1.2}
		for i: int in range(int(fixture.steps)):
			sim.drive(sample, float(fixture.command.s), float(fixture.command.t), float(fixture.command.b))
		var name: String = str(fixture.profile) + "/" + str(fixture.name)
		close(sim.speed, float(fixture.speed), name + " speed")
		close(sim.lateral, float(fixture.lateral), name + " lateral")
		close(sim.slip, float(fixture.slip), name + " slip")
		check(sim.drifting == bool(fixture.drifting), name + " drift")
	var race: RacerSimulation = RacerSimulation.new()
	race.traffic_enabled = false
	for i: int in range(60):
		race.advance(1.0 / 60, 0, 1, 0, false)
	check(race.phase == "countdown", "Countdown blocks driving")
	close(race.distance, 0, "Countdown distance")
	race.set_paused(true)
	var countdown: float = race.countdown
	race.advance(1, 0, 1, 0, true)
	close(race.countdown, countdown, "Pause freezes countdown")
	race.set_paused(false)
	for i: int in range(150):
		race.advance(1.0 / 60, 0, 1, 0, false)
	check(race.phase == "racing" and race.distance > 0, "Countdown transitions to driving")
	var old_elapsed: float = race.elapsed
	race.advance(4, 0, 1, 0, false)
	check(race.elapsed - old_elapsed <= 0.1 + 0.000001, "Fixed-step catch-up is bounded")
	check(race.dropped_time > 3.8, "Dropped time is accounted for")
	var first: RacerSimulation = RacerSimulation.new()
	var second: RacerSimulation = RacerSimulation.new()
	first.countdown = 0
	second.countdown = 0
	for i: int in range(1000):
		first.advance(1.0 / 60, 0.1, 1, 0, false)
		second.advance(1.0 / 60, 0.1, 1, 0, false)
	close(first.distance, second.distance, "Seeded simulation determinism")
	check(first.traffic == second.traffic, "Seeded traffic determinism")
	first.phase = "racing"
	first.finish_stage(first.track.sections["city-fork"])
	check(first.stage_id == "city-axis-tunnel", "Checkpoint follows the course chosen before racing")
	for destination: String in ["city-axis-tunnel", "peaks-storm-switchback"]:
		for side: int in [-1, 1]:
			var locked: RacerSimulation = RacerSimulation.new("neon-loop", "standard", 1, [destination])
			locked.phase = "racing"
			locked.traffic_enabled = false
			locked.stage_id = "city-fork"
			locked.stage_start = locked.track.starts[locked.track.path.find(locked.stage_id)]
			locked.distance = locked.stage_start + float(locked.track.sections[locked.stage_id].length) - 0.5
			locked.previous_distance = locked.distance
			locked.speed = 110
			locked.lateral = side * 0.35
			var revision: int = locked.track.revision
			var positions: PackedVector3Array = locked.track.positions.duplicate()
			var path: Array[String] = locked.track.path.duplicate()
			locked.advance(1.0 / 60, side, 1, 0, false)
			check(locked.stage_id == destination, "Steering cannot change the preselected course: " + destination)
			check(locked.track.path == path and locked.track.positions == positions and locked.track.revision == revision,
				"Crossing a fork never rebuilds the predetermined level")
	var finisher: RacerSimulation = RacerSimulation.new()
	finisher.phase = "racing"
	finisher.finish_stage(finisher.track.sections["peaks-summit-finish"])
	check(finisher.phase == "finished", "Terminal stage finishes race")
	close(finisher.score, 500, "Finish bonus")
	var frozen: float = finisher.score
	finisher.advance(1, 0, 1, 0, true)
	close(finisher.score, frozen, "Finished race freezes scoring")
	test_crashes()
	test_offroad_recovery()
	test_collision_geometry()
	test_branch_frames(native_track)
	test_route_reuse()
	var profile: RacerProfileStore = RacerProfileStore.new("user://test-profile-%d.json" % OS.get_process_id())
	check(profile.valid_profile(profile.profile), "Default profile validates")
	profile.profile.settings.music = 0.25
	check(profile.save(), "Profile saves")
	var loaded: RacerProfileStore = RacerProfileStore.new(profile.save_path)
	check(loaded.load_profile(), "Profile loads")
	close(float(loaded.profile.settings.music), 0.25, "Settings persist")
	profile.record(finisher)
	check(int(profile.profile.races) == 1, "Finish records accomplishment")
	profile.record(race)
	check(int(profile.profile.races) == 1, "Incomplete run does not count")
	check(profile.unlocks().has("solar-flare"), "First finish unlocks palette")
	profile.profile.races = 3
	check(profile.unlocks().has("vector-sprint"), "Three finishes unlock vehicle")
	profile.profile.gold = 2
	check(profile.unlocks().has("apex-phantom"), "Two gold finishes unlock vehicle")
	profile.reset()
	close(float(profile.profile.settings.music), 0.25, "Reset preserves audio")
	check(int(profile.profile.races) == 0, "Reset clears progression")
	var corrupt: Dictionary = profile.profile.duplicate(true)
	corrupt.vehicle = "unknown"
	check(not profile.valid_profile(corrupt), "Invalid vehicle fails recovery validation")
	corrupt = profile.profile.duplicate(true)
	corrupt.settings.music = 2.0
	check(not profile.valid_profile(corrupt), "Invalid volume fails recovery validation")
	var result: Error = DirAccess.remove_absolute(profile.save_path)
	check(result == OK, "Temporary test profile cleaned up")
	for route: Dictionary in RacerCatalog.ROUTES:
		for kind: String in ["novice", "standard", "expert"]:
			var track: RacerTrack = RacerTrack.new(str(route.id), kind)
			check(track.total_length > 0 and track.path.size() >= 3, "Route builds: " + str(route.id) + "/" + kind)
			check(track.frame(-20).origin.z > track.frame(0).origin.z, "Launch road extends behind car")
			check(track.frame(track.total_length + 20).origin != track.frame(track.total_length).origin,
				"Finish road extrapolates")
	for route_id: String in ["neon-loop", "skyline-run", "void-causeway"]:
		var full_run: RacerSimulation = RacerSimulation.new(route_id)
		full_run.phase = "racing"
		full_run.traffic_enabled = false
		for i: int in range(12000):
			var d: float = full_run.distance - full_run.stage_start
			var sample: Dictionary = full_run.track.driving_sample(full_run.stage_id, d, full_run.split_side)
			var path_sample: Dictionary = full_run.track.split_path(full_run.stage_id, d, full_run.split_side)
			var local: float = full_run.lateral
			if not path_sample.is_empty():
				var aggregate: Dictionary = full_run.track.sample(full_run.stage_id, d)
				local = (full_run.lateral * float(aggregate.half_width) - float(path_sample.center)) / float(path_sample.half_width)
			var ratio: float = clampf(full_run.speed / float(full_run.config.maximum_speed), 0, 1)
			var authority: float = lerpf(float(full_run.config.rest_ratio), 1, ratio) * clampf(full_run.speed / 8, 0, 1)
			var correction: float = (float(sample.curvature) * full_run.speed * full_run.speed
				* float(full_run.config.centrifugal)) / maxf(0.01, float(full_run.config.steering_rate) * authority)
			if full_run.drifting:
				correction /= float(full_run.config.drift_steering)
			var target: float = 0.0
			var stage: Dictionary = full_run.track.sections[full_run.stage_id]
			if stage.links.size() > 1:
				target = -0.35
			full_run.advance(1.0 / 60, clampf(correction + (target - local) * 2, -1, 1), 1, 0, false)
			if full_run.phase in ["finished", "failed"]:
				break
		check(full_run.phase == "finished", "Complete playable route: " + route_id)
		check(full_run.breakdown.has("finish"), "Full run awards finish bonus: " + route_id)
	print("Godot core: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func test_crashes() -> void:
	for side: int in [-1, 1]:
		var sim: RacerSimulation = RacerSimulation.new()
		sim.phase = "racing"
		sim.traffic_enabled = false
		sim.speed = 120
		sim.lateral = side * 0.5
		sim.crash(0.75)
		check(sim.wipeout_direction == side, "Crash pushes away from the impact")
		close(sim.speed, 72, "Crash applies initial slowdown")
		close(sim.wipeout_duration, 2.15, "Native severity-based wipeout duration")
		var start_lateral: float = sim.lateral
		for i: int in range(24):
			sim.advance(1.0 / 60, -side, 1, 0, true)
		check(sim.distance > 10, "Crash slides forward rather than spinning in place")
		check(absf(sim.lateral) > absf(start_lateral), "Crash slides sideways despite steering toward the center")
		check(not sim.boosting and sim.speed < 72, "Wipeout blocks acceleration and boost")
		var frozen: float = sim.wipeout
		sim.set_paused(true)
		sim.advance(0.1, 0, 1, 0, false)
		close(sim.wipeout, frozen, "Pause freezes crash recovery")
		sim.set_paused(false)
		for i: int in range(110):
			sim.advance(1.0 / 60, 0, 0, 0, false)
		close(sim.wipeout, 0, "Crash recovery completes")
		close(sim.lateral, 0, "Respawn returns to road center")
		close(sim.speed, 0, "Respawn is stationary")
		check(sim.shield > 1.6 and not sim.offroad, "Respawn shield protects a cleared road state")
		var score: float = sim.score
		sim.crash(1)
		close(sim.score, score, "Shield prevents repeated collision penalties")
	for side: int in [-1, 1]:
		var sim: RacerSimulation = RacerSimulation.new()
		sim.phase = "racing"
		sim.traffic_enabled = false
		sim.stage_id = "coast-solar-sweep"
		sim.stage_start = sim.track.starts[sim.track.path.find(sim.stage_id)]
		sim.distance = sim.stage_start + 525
		sim.previous_distance = sim.distance
		sim.split_side = side
		var cross: Dictionary = sim.track.at_distance(sim.distance).split
		sim.lateral = float(cross.left_center if side < 0 else cross.right_center) / float(cross.half_width)
		sim.crash(0.5, sim.lateral - 0.01)
		for i: int in range(130):
			sim.advance(1.0 / 60, 0, 0, 0, false)
		var path: Dictionary = sim.track.split_path(sim.stage_id, sim.distance - sim.stage_start, side)
		var aggregate: Dictionary = sim.track.at_distance(sim.distance)
		close(sim.lateral, float(path.center) / float(aggregate.half_width), "Split-road respawn stays on its branch")
		check(sim.split_side == side and sim.shield > 0, "Split-road recovery preserves branch and shield")


func test_offroad_recovery() -> void:
	for kind: String in ["novice", "standard", "expert"]:
		var sim: RacerSimulation = RacerSimulation.new("neon-loop", kind)
		for side: int in [-1, 1]:
			for offset: float in [1.05, 1.45]:
				for strength: float in [0.25, 1.0]:
					for initial_speed: float in [0.0, 1.0, float(sim.config.maximum_speed) * float(sim.config.boost_multiplier)]:
						for curvature: float in [-0.85, 0.0, 0.85]:
							for control: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)]:
								sim.lateral = side * offset
								sim.speed = initial_speed
								sim.boosting = initial_speed > float(sim.config.maximum_speed)
								sim.drifting = false
								sim.was_braking = false
								var sample: Dictionary = {"curvature": curvature, "grade": 0.2,
									"half_width": 6.0, "shoulder": 1.2}
								var moving_inward: bool = true
								for step: int in range(1200):
									if absf(sim.lateral) <= 1:
										break
									var before: float = absf(sim.lateral)
									sim.drive(sample, -side * strength, control.x, control.y)
									moving_inward = moving_inward and absf(sim.lateral) < before
								var name: String = "%s/%d/%.2f/%.2f/%.1f/%.2f/%s" % [
									kind, side, offset, strength, initial_speed, curvature, control]
								check(moving_inward and absf(sim.lateral) <= 1 and not sim.offroad,
									"Inward steering always recovers onto asphalt: " + name)
		sim.speed = 0
		sim.lateral = 1.45
		sim.boosting = false
		sim.drifting = false
		var flat: Dictionary = {"curvature": 0.0, "grade": 0.0, "half_width": 6.0, "shoulder": 1.2}
		sim.drive(flat, 0, 0, 0)
		close(sim.lateral, 1.45, "Off-road recovery requires player steering")
		sim.lateral = 0
		sim.drive(flat, 1, 0, 0)
		close(sim.lateral, 0, "Stationary on-road handling retains the native motion gate")
		for route: String in ["neon-loop", "skyline-run"]:
			for branch: int in [-1, 1]:
				for edge: int in [-1, 1]:
					var split_sim: RacerSimulation = RacerSimulation.new(route, kind)
					split_sim.phase = "racing"
					split_sim.traffic_enabled = false
					split_sim.stage_id = "coast-solar-sweep" if route == "neon-loop" else "skyline-1"
					split_sim.stage_start = split_sim.track.starts[split_sim.track.path.find(split_sim.stage_id)]
					split_sim.distance = split_sim.stage_start + float(split_sim.track.sections[split_sim.stage_id].length) * 0.5
					split_sim.previous_distance = split_sim.distance
					split_sim.split_side = branch
					var path: Dictionary = split_sim.track.split_path(split_sim.stage_id,
						split_sim.distance - split_sim.stage_start, branch)
					var aggregate: Dictionary = split_sim.track.at_distance(split_sim.distance)
					split_sim.lateral = (float(path.center) + edge * 1.45 * float(path.half_width)) / float(aggregate.half_width)
					split_sim.previous_lateral = split_sim.lateral
					for step: int in range(240):
						split_sim.advance(1.0 / 60, -edge, 0, 0, false)
						var local: float = (split_sim.lateral * float(aggregate.half_width) - float(path.center)) / float(path.half_width)
						if absf(local) <= 1:
							break
					var recovered: float = (split_sim.lateral * float(aggregate.half_width) - float(path.center)) / float(path.half_width)
					check(absf(recovered) <= 1 and not split_sim.offroad and split_sim.split_side == branch,
						"Stationary recovery stays on the chosen split branch: %s/%s/%d/%d" % [route, kind, branch, edge])
					var distance_before: float = split_sim.distance
					for step: int in range(60):
						split_sim.advance(1.0 / 60, 0, 1, 0, false)
					check(split_sim.speed > 0 and split_sim.distance > distance_before,
						"Recovered split-road car can accelerate again")


func test_branch_frames(track: RacerTrack) -> void:
	var start: float = track.starts[track.path.find("coast-solar-sweep")]
	for side: int in [-1, 1]:
		for offset: float in [225.0, 300.0, 525.0, 795.0, 855.0]:
			var cross: Dictionary = track.split_cross("coast-solar-sweep", offset)
			var path: Dictionary = track.split_path("coast-solar-sweep", offset, side)
			var center: float = float(path.center)
			var frame: Transform3D = track.branch_frame(start + offset, side)
			var actor: Transform3D = track.actor_frame(start + offset, center / float(cross.half_width), side)
			close(frame.origin.distance_to(actor.origin), 0, "Branch geometry and vehicle share their center", 0.00001)
			close(frame.basis.x.dot(actor.basis.x), 1, "Branch geometry and vehicle share their heading", 0.00001)
			var ahead: Vector3 = -frame.basis.z
			var base: Transform3D = track.frame(start + offset)
			var expected: Vector3 = base.origin + base.basis.x * center + Vector3.UP * float(path.elevation)
			close(frame.origin.distance_to(expected), 0, "Branch elevation stays above the common centerline", 0.00001)
			var grade: float = float(track.sample("coast-solar-sweep", offset).grade) + float(path.grade)
			close(ahead.y / Vector2(ahead.x, ahead.z).length(), grade, "Branch frame includes split grade", 0.00001)
	close(track.frame(-20).basis.z.y, 0, "Launch extension is level")
	close(track.frame(track.total_length + 20).basis.z.y, 0, "Finish extension is level")


func test_collision_geometry() -> void:
	for side: int in [-1, 1]:
		var sim: RacerSimulation = RacerSimulation.new()
		sim.phase = "racing"
		sim.stage_id = "coast-solar-sweep"
		sim.stage_start = sim.track.starts[sim.track.path.find(sim.stage_id)]
		sim.distance = sim.stage_start + 525
		sim.previous_distance = sim.distance
		sim.split_side = side
		var sample: Dictionary = sim.track.at_distance(sim.distance)
		var cross: Dictionary = sample.split
		sim.lateral = float(cross.left_center if side < 0 else cross.right_center) / float(cross.half_width)
		sim.next_spawn = INF
		sim.next_obstacle = INF
		var neighboring_lane: float = sim.lateral + 4.0 / float(sample.half_width)
		sim.obstacles.append({"distance": sim.distance, "lateral": neighboring_lane, "hit": false})
		sim.update_traffic()
		close(sim.wipeout, 0, "Wide split envelope does not enlarge obstacle collision boxes")
		check(not sim.intersects_actor(sim.distance, neighboring_lane, 0.2, 0.8), "Four-meter gap is clear on a split road")
		sim.obstacles[0].lateral = sim.lateral + 1.0 / float(sample.half_width)
		sim.update_traffic()
		check(sim.wipeout > 0 and sim.obstacles[0].hit, "Visible obstacle overlap causes a crash on either branch")
		var spawner: RacerSimulation = RacerSimulation.new()
		spawner.stage_id = sim.stage_id
		spawner.stage_start = sim.stage_start
		spawner.distance = sim.distance
		spawner.next_obstacle = sim.distance + 250
		spawner.next_spawn = INF
		spawner.update_traffic()
		check(spawner.obstacles.size() == 1, "Split-road obstacle spawns ahead")
		var obstacle: Dictionary = spawner.obstacles[0]
		var lanes: PackedFloat64Array = spawner.track.lane_centers(spawner.stage_id, float(obstacle.distance) - spawner.stage_start)
		check(lanes.has(float(obstacle.lateral)), "Obstacles spawn on physical branch lanes, not the terrain island")


func test_route_reuse() -> void:
	for route: String in ["neon-loop", "skyline-run", "void-causeway"]:
		var track: RacerTrack = RacerTrack.new(route)
		var revision: int = track.revision
		var committed: Array[String] = []
		var initial: PackedVector3Array = track.positions.duplicate()
		var path: Array[String] = track.path.duplicate()
		for id: String in path:
			committed.append(id)
			check(not track.rebuild(committed), "Ordinary checkpoint reuses track geometry: " + route)
			check(track.revision == revision, "Checkpoint does not invalidate render chunks: " + route)
		check(track.positions == initial, "Ordinary checkpoints preserve every centerline sample: " + route)
		for index: int in range(1, track.starts.size()):
			var boundary: float = track.starts[index]
			var before: Dictionary = track.presentation_sample(boundary - 0.05)
			var after: Dictionary = track.presentation_sample(boundary + 0.05)
			check(absf(float(after.half_width) - float(before.half_width)) < 0.02,
				"Checkpoint road widths taper smoothly: " + route)
			check(absf(float(after.lanes) - float(before.lanes)) < 0.01,
				"Checkpoint lane markings crossfade smoothly: " + route)
	var branched: RacerTrack = RacerTrack.new()
	var fork_index: int = branched.path.find("city-fork")
	var boundary: float = branched.starts[fork_index] + float(branched.sections["city-fork"].length)
	var old_frame: Transform3D = branched.frame(boundary - 24)
	check(branched.rebuild(["peaks-storm-switchback"]), "Choosing an alternate branch changes the route")
	check(branched.frame(boundary - 24).is_equal_approx(old_frame), "A fork preserves the road already traveled")
	var fresh: RacerTrack = RacerTrack.new()
	fresh.path.clear()
	fresh.rebuild(["peaks-storm-switchback"])
	for distance: float in [boundary - 5, boundary, boundary + 5, boundary + 180, branched.total_length - 5]:
		close(branched.frame(distance).origin.distance_to(fresh.frame(distance).origin), 0,
			"Incremental fork geometry agrees with a freshly built route", 0.0001)

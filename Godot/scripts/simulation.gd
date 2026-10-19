class_name RacerSimulation
extends RefCounted

signal feedback(message: String)
signal completed(success: bool)

const STEP: float = 1.0 / 120.0
const MAX_TRAFFIC: int = 12
const MAX_OBSTACLES: int = 4
var track: RacerTrack
var config: Dictionary
var phase: String = "countdown"
var phase_before_pause: String = "countdown"
var countdown: float = 3.0
var elapsed: float = 0.0
var remaining: float
var distance: float = 0.0
var previous_distance: float = 0.0
var lateral: float = 0.0
var previous_lateral: float = 0.0
var speed: float = 0.0
var slip: float = 0.0
var boost: float
var boosting: bool = false
var boost_cooldown: float = 0.0
var offroad: bool = false
var drifting: bool = false
var drift_duration: float = 0.0
var drift_peak: float = 0.0
var was_braking: bool = false
var wipeout: float = 0.0
var wipeout_duration: float = 0.0
var wipeout_direction: float = 0.0
var wipeout_severity: float = 0.0
var shield: float = 0.0
var combo: int = 0
var combo_time: float = 0.0
var slow_time: float = 0.0
var score: float = 0.0
var breakdown: Dictionary = {}
var traffic: Array[Dictionary] = []
var obstacles: Array[Dictionary] = []
var committed: Array[String] = []
var accumulator: float = 0.0
var dropped_time: float = 0.0
var traffic_enabled: bool = true
var random: RandomNumberGenerator = RandomNumberGenerator.new()
var next_spawn: float = 290.0
var next_obstacle: float = 460.0
var stage_id: String
var stage_start: float = 0.0
var fork_announced: bool = false
var split_side: int = 0
var steering_input: float = 0.0
var braking_input: float = 0.0


func _init(route_id: String = "neon-loop", kind: String = "standard", seed: int = 1, choices: Array[String] = []) -> void:
	config = RacerCatalog.configuration(kind)
	track = RacerTrack.new(route_id, kind, choices)
	remaining = float(config.duration)
	boost = float(config.initial_charge)
	stage_id = track.start_id
	random.seed = seed


func advance(delta: float, steering: float, throttle: float, brake: float, wants_boost: bool) -> void:
	if phase in ["paused", "finished", "failed"] or not is_finite(delta):
		return
	var clamped: float = clampf(delta, 0, 0.25)
	dropped_time += maxf(0, delta - clamped)
	accumulator += clamped
	var steps: int = 0
	while accumulator + STEP * 0.000001 >= STEP and steps < 12:
		previous_distance = distance
		previous_lateral = lateral
		tick(clampf(steering, -1, 1), clampf(throttle, 0, 1), clampf(brake, 0, 1), wants_boost)
		accumulator = maxf(0, accumulator - STEP)
		steps += 1
		if phase in ["finished", "failed"]:
			accumulator = 0
			break
	if steps == 12 and accumulator + STEP * 0.000001 >= STEP:
		dropped_time += accumulator
		accumulator = 0


func set_paused(paused: bool) -> void:
	if paused and phase in ["countdown", "racing"]:
		phase_before_pause = phase
		phase = "paused"
	elif not paused and phase == "paused":
		phase = phase_before_pause


func tick(steering: float, throttle: float, brake: float, wants_boost: bool) -> void:
	steering_input = steering
	braking_input = brake
	if phase == "countdown":
		countdown = maxf(0, countdown - STEP)
		if countdown == 0:
			phase = "racing"
			feedback.emit("GO!")
		return
	var stage_distance: float = distance - stage_start
	var aggregate: Dictionary = track.sample(stage_id, stage_distance)
	if not aggregate.split.is_empty() and split_side == 0:
		split_side = (-1 if lateral < 0 else 1) if absf(lateral) > 0.05 else (1 if steering > 0.05 else -1)
	var path_sample: Dictionary = track.split_path(stage_id, stage_distance, split_side)
	if not path_sample.is_empty():
		lateral = (lateral * float(aggregate.half_width) - float(path_sample.center)) / float(path_sample.half_width)
	var sample: Dictionary = track.driving_sample(stage_id, stage_distance, split_side)
	var was_boosting: bool = boosting
	boost_cooldown = maxf(0, boost_cooldown - STEP)
	boosting = wants_boost and throttle > brake and boost_cooldown == 0 and wipeout == 0
	if boosting and not was_boosting:
		boosting = boost >= 0.2
		if boosting:
			boost -= 0.2
	elif boosting:
		boosting = boost > 0
	if wipeout > 0:
		speed = maxf(0, speed - maxf(float(config.braking) * 1.25, speed * 1.8) * STEP)
		lateral = clampf(lateral + wipeout_direction * 0.55 * wipeout / wipeout_duration * STEP, -1.45, 1.45)
		wipeout = maxf(0, wipeout - STEP)
		drifting = false
		slip = 0.0
		if wipeout == 0:
			speed = 0.0
			lateral = 0.0
			offroad = false
			wipeout_duration = 0.0
			wipeout_direction = 0.0
			wipeout_severity = 0.0
			shield = 1.8
	else:
		drive(sample, steering, throttle, brake)
	shield = maxf(0, shield - STEP)
	var moved: float = speed * STEP / (float(path_sample.distance_scale) if not path_sample.is_empty() else 1.0)
	distance += moved
	if split_side != 0:
		var next_path: Dictionary = track.split_path(stage_id, stage_distance + moved, split_side)
		var next_aggregate: Dictionary = track.sample(stage_id, stage_distance + moved)
		var local_half: float = (float(next_path.half_width) if not next_path.is_empty()
			else float(track.sections[stage_id].lanes.count) * float(track.sections[stage_id].lanes.width) / 2.0)
		lateral = ((float(next_path.center) if not next_path.is_empty() else 0.0) + lateral * local_half) \
			/ float(next_aggregate.half_width)
		if next_path.is_empty():
			split_side = 0
	elapsed += STEP
	remaining = maxf(0, remaining - STEP)
	award("distance", moved)
	var threshold: float = float(config.maximum_speed) * 0.7
	if speed > threshold:
		award("speed", 1.5 * (speed - threshold) /
			(float(config.maximum_speed) * float(config.boost_multiplier) - threshold) * STEP)
	if boosting:
		boost = maxf(0, boost - float(config.consumption) * STEP)
		award("boost", float(config.boost_points) * STEP)
	elif not wants_boost:
		boost = minf(float(config.capacity), boost + float(config.recharge) * STEP)
	if combo > 0:
		combo_time += STEP
		slow_time = slow_time + STEP if speed < float(config.maximum_speed) * 0.2 else 0.0
		if slow_time >= 3:
			combo = 0
		elif combo_time >= 3:
			combo = maxi(0, combo - 1)
			combo_time = 2.0
	if traffic_enabled:
		update_traffic()
	var stage: Dictionary = track.sections[stage_id]
	var stage_remaining: float = float(stage.length) - (distance - stage_start)
	if stage.links.size() > 1 and stage_remaining < 500 and not fork_announced:
		fork_announced = true
		feedback.emit("COURSE AHEAD  /  " + next_stage_id().replace("-", " ").to_upper())
	if remaining <= 0:
		phase = "failed"
		completed.emit(false)
	elif stage_remaining <= 0:
		finish_stage(stage)


func drive(sample: Dictionary, steering: float, throttle: float, brake: float) -> void:
	offroad = absf(lateral) > 1 + float(sample.shoulder) / float(sample.half_width)
	var drag: float = float(config.drag) + (float(config.offroad_drag) if offroad else 0.0)
	speed += (throttle * float(config.acceleration) - brake * float(config.braking)
		+ (float(config.boost_acceleration) if boosting else 0.0)
		- clampf(float(sample.grade), -0.2, 0.2) * float(config.grade_scale)
		- (drag if speed > 0 else 0.0)) * STEP
	speed = clampf(speed, 0, float(config.maximum_speed) *
		(float(config.boost_multiplier) if boosting else 1.0))
	var ratio: float = clampf(speed / float(config.maximum_speed), 0, 1)
	var authority: float = lerpf(float(config.rest_ratio), 1, ratio) * clampf(speed / 8, 0, 1)
	var brake_tap: bool = brake >= float(config.drift_brake) and not was_braking
	was_braking = brake >= float(config.drift_brake)
	if not drifting and absf(steering) >= float(config.drift_hard) and ratio >= float(config.drift_min):
		if brake_tap or (absf(float(sample.curvature)) >= float(config.drift_curve)
				and signf(steering) == signf(float(sample.curvature))
				and ratio >= float(config.drift_curve_speed)):
			drifting = true
			drift_duration = 0.0
			drift_peak = 0.0
	if drifting and (absf(steering) < float(config.drift_exit) or ratio < float(config.drift_min) * 0.75):
		if drift_duration >= 0.25 and drift_peak >= 0.2:
			skill("drift", 45 * minf(3, drift_duration) * drift_peak,
				minf(0.75, 0.18 * minf(3, drift_duration) * drift_peak))
		drifting = false
	var intensity: float = minf(1, maxf(absf(steering), maxf(absf(float(sample.curvature)), ratio)))
	if drifting:
		drift_duration += STEP
		drift_peak = maxf(drift_peak, intensity)
	var lateral_delta: float = steering * float(config.steering_rate) * authority * STEP \
		* (float(config.offroad_grip) if offroad else 1.0) \
		* (float(config.drift_steering) if drifting else 1.0) \
		- float(sample.curvature) * speed * speed * float(config.centrifugal) * STEP
	if absf(lateral) > 1 and steering * lateral < 0:
		# Preserve inward control when drag stops the car or a curve pushes it outward.
		var recovery_delta: float = steering * float(config.steering_rate) * float(config.rest_ratio) * STEP \
			* (float(config.offroad_grip) if offroad else 1.0)
		lateral_delta = minf(lateral_delta, recovery_delta) if lateral > 0 else maxf(lateral_delta, recovery_delta)
	lateral += lateral_delta
	offroad = absf(lateral) > 1 + float(sample.shoulder) / float(sample.half_width)
	if offroad:
		speed = minf(speed, maxf(float(config.maximum_speed) * float(config.offroad_limit),
			speed - float(config.offroad_drag) * STEP))
	if absf(lateral) > 1.45:
		lateral = clampf(lateral, -1.45, 1.45)
		speed = maxf(0, speed - float(config.wall_loss) * STEP)
	if drifting:
		speed = maxf(0, speed - float(config.drift_loss) * intensity * STEP)
	slip = lerpf(slip, signf(steering) * 0.35 * intensity if drifting else 0.0, 8.0 * STEP)


func award(source: String, points: float) -> void:
	score += points
	breakdown[source] = float(breakdown.get(source, 0.0)) + points


func skill(source: String, points: float, charge: float) -> void:
	combo += 1
	combo_time = 0.0
	slow_time = 0.0
	award(source, points * minf(4, 1 + int(combo / 2.0) * 0.25))
	boost = minf(float(config.capacity), boost + charge)
	feedback.emit(source.replace("_", " ").to_upper() + "!")


func finish_stage(stage: Dictionary) -> void:
	if stage.links.is_empty():
		award("finish", 500)
		phase = "finished"
		completed.emit(true)
		return
	var index: int = track.path.find(str(stage.id))
	assert(index >= 0 and index + 1 < track.path.size(), "Checkpoint must belong to the prepared course.")
	stage_start += float(stage.length)
	stage_id = track.path[index + 1]
	split_side = 0
	committed.append(stage_id)
	fork_announced = false
	if float(stage.award) > 0:
		skill("checkpoint", 150, 0)
		remaining += float(stage.award)
		feedback.emit("CHECKPOINT  +%ds" % int(stage.award))


func next_stage_id() -> String:
	var index: int = track.path.find(stage_id)
	return track.path[index + 1] if index + 1 < track.path.size() else ""


func update_traffic() -> void:
	var stage: Dictionary = track.sections[stage_id]
	var stage_end: float = stage_start + float(stage.length)
	if distance + 700 >= next_spawn and next_spawn < stage_end - 150 and traffic.size() < MAX_TRAFFIC:
		var spawn_distance: float = maxf(distance + 250, next_spawn)
		var centers: PackedFloat64Array = track.lane_centers(stage_id, spawn_distance - stage_start)
		var lane: int = random.randi_range(0, centers.size() - 1)
		var occupied: bool = false
		var offset: float = centers[lane]
		for other: Dictionary in traffic:
			if absf(float(other.distance) - spawn_distance) < 58 and absf(float(other.lateral) - offset) < 0.3:
				occupied = true
		if not occupied and spawn_distance < stage_end - 150:
			traffic.append({"distance": spawn_distance, "lateral": offset,
				"speed": random.randf_range(58, 98), "lane": lane, "passed": false, "hit": false,
				"color": Color.from_hsv(random.randf(), 0.75, 0.8)})
		next_spawn = spawn_distance + 100 + random.randf() * 110
	if distance + 500 >= next_obstacle and next_obstacle < stage_end - 150 and obstacles.size() < MAX_OBSTACLES:
		var spawn_distance: float = maxf(distance + 250, next_obstacle)
		if spawn_distance < stage_end - 150:
			var centers: PackedFloat64Array = track.lane_centers(stage_id, spawn_distance - stage_start)
			obstacles.append({"distance": spawn_distance,
				"lateral": centers[0] if random.randf() < 0.5 else centers[-1], "hit": false})
		next_obstacle = spawn_distance + 420
	for vehicle: Dictionary in traffic:
		var old_relative: float = float(vehicle.distance) - previous_distance
		vehicle.distance = float(vehicle.distance) + float(vehicle.speed) * STEP
		var vehicle_sample: Dictionary = track.at_distance(float(vehicle.distance))
		var centers: PackedFloat64Array = track.lane_centers(str(vehicle_sample.id), float(vehicle_sample.distance))
		vehicle.lateral = centers[mini(int(vehicle.lane), centers.size() - 1)]
		var relative: float = float(vehicle.distance) - distance
		var gap: float = absf(float(vehicle.lateral) - lateral)
		if absf(relative) < 6 and not bool(vehicle.hit) and shield == 0 and wipeout == 0 \
				and intersects_actor(float(vehicle.distance), float(vehicle.lateral), 2.225, 1.01):
			vehicle.hit = true
			crash(0.65, float(vehicle.lateral))
		elif old_relative > 0 and relative <= 0 and not bool(vehicle.passed) and not bool(vehicle.hit):
			vehicle.passed = true
			if gap < 0.42:
				skill("near_miss", 80 + 120 * (1 - gap / 0.42), 0.5)
			else:
				skill("overtake", 120, 0.3)
	for obstacle: Dictionary in obstacles:
		if absf(float(obstacle.distance) - distance) < 6 \
				and intersects_actor(float(obstacle.distance), float(obstacle.lateral), 0.2, 0.8):
			if not bool(obstacle.hit) and shield == 0 and wipeout == 0:
				obstacle.hit = true
				crash(0.35, float(obstacle.lateral))
	traffic = traffic.filter(func(v: Dictionary) -> bool: return float(v.distance) > distance - 80)
	obstacles = obstacles.filter(func(v: Dictionary) -> bool: return float(v.distance) > distance - 80)
	if next_spawn < distance:
		next_spawn = distance + 250
	if next_obstacle < distance:
		next_obstacle = distance + 420


func intersects_actor(other_distance: float, other_lateral: float, half_length: float, half_width: float) -> bool:
	var player: Transform3D = track.actor_frame(distance, lateral, split_side)
	var other: Transform3D = track.actor_frame(other_distance, other_lateral)
	var offset: Vector3 = player.basis.inverse() * (other.origin - player.origin)
	return absf(offset.x) <= 1.01 + half_width and absf(offset.z) <= 2.225 + half_length and absf(offset.y) <= 1.25


func crash(severity: float, obstacle_lateral: float = 0.0) -> void:
	if wipeout > 0 or shield > 0:
		return
	var aggregate: Dictionary = track.at_distance(distance)
	var local_path: Dictionary = track.split_path(stage_id, distance - stage_start, split_side)
	var local: float = lateral
	var obstacle_local: float = obstacle_lateral
	if not local_path.is_empty():
		local = (lateral * float(aggregate.half_width) - float(local_path.center)) / float(local_path.half_width)
		obstacle_local = (obstacle_lateral * float(aggregate.half_width) - float(local_path.center)) / float(local_path.half_width)
	wipeout_direction = -1.0 if local < obstacle_local else 1.0
	local = clampf(local + wipeout_direction * 0.11, -1, 1)
	lateral = ((float(local_path.center) + local * float(local_path.half_width)) / float(aggregate.half_width)
		if not local_path.is_empty() else local)
	speed *= 0.60
	award("collision", -(100 + 300 * severity))
	combo = 0
	boost = maxf(0, boost - 0.75)
	boost_cooldown = 1.25
	boosting = false
	wipeout_severity = clampf(severity, 0, 1)
	wipeout_duration = 1.7 + 0.6 * wipeout_severity
	wipeout = wipeout_duration
	feedback.emit("CRASH!")


func rank() -> String:
	for tier: String in ["gold", "silver", "bronze"]:
		if score >= float(config[tier]):
			return tier
	return "unranked"


func render_distance() -> float:
	return lerpf(previous_distance, distance, clampf(accumulator / STEP, 0, 1))


func render_lateral() -> float:
	return lerpf(previous_lateral, lateral, clampf(accumulator / STEP, 0, 1))

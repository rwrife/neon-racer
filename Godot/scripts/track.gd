class_name RacerTrack
extends RefCounted

const PRESENTATION_TRANSITION: float = 60.0

var sections: Dictionary = {}
var start_id: String
var path: Array[String] = []
var starts: PackedFloat64Array = []
var positions: PackedVector3Array = []
var headings: PackedFloat64Array = []
var total_length: float = 0.0
var revision: int = 0


func _init(route_id: String = "neon-loop", kind: String = "standard", choices: Array[String] = []) -> void:
	var reference: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/swift-reference.json"))
	var route: Dictionary = reference.routes[route_id + "/" + kind]
	for stage: Dictionary in route.graph.stages:
		var profile: Dictionary = route.profiles[stage.id]
		var links: Array[Dictionary] = []
		for branch: Dictionary in stage.branches:
			links.append({"destinationSectionID": branch.destinationStageID})
		var section: Dictionary = {
			"id": stage.id, "length": stage.distance,
			"curve": {"entry": profile.curveEntry, "apex": profile.curveApex, "exit": profile.curveExit},
			"elevation": {"startMeters": profile.elevationStart, "endMeters": profile.elevationEnd},
			"lanes": {"count": profile.laneCount, "width": profile.laneWidth, "shoulderWidth": profile.shoulderWidth},
			"links": links, "award": stage.checkpointTimeAward, "environment": stage.environmentID,
		}
		if profile.has("elevationCrest"):
			section.elevation["crestMeters"] = profile.elevationCrest
		sections[stage.id] = section
	start_id = str(route.graph.startStageID)
	rebuild(choices)


func rebuild(committed: Array[String]) -> bool:
	var next_path: Array[String] = []
	var next_starts: PackedFloat64Array = []
	var id: String = start_id
	var next_length: float = 0.0
	while not id.is_empty():
		assert(not next_path.has(id), "Cyclic route: " + id)
		next_path.append(id)
		next_starts.append(next_length)
		var section: Dictionary = sections[id]
		next_length += float(section.length)
		var links: Array = section.links
		if links.is_empty():
			break
		var next_id: String = str(links[0].destinationSectionID)
		for link: Dictionary in links:
			if committed.has(str(link.destinationSectionID)):
				next_id = str(link.destinationSectionID)
		id = next_id
	if next_path == path:
		return false
	var shared: int = 0
	while shared < mini(path.size(), next_path.size()) and path[shared] == next_path[shared]:
		shared += 1
	var boundary: float = next_starts[shared] if shared < next_starts.size() else next_length
	var keep: int = mini(positions.size(), int(floor(boundary / 5.0)) + 1) if shared > 0 else 0
	path = next_path
	starts = next_starts
	total_length = next_length
	positions.resize(keep)
	headings.resize(keep)
	var position: Vector3 = positions[-1] if keep > 0 else Vector3.ZERO
	var heading: float = headings[-1] if keep > 0 else 0.0
	var last_elevation: float = position.y
	for i: int in range(keep, int(ceil(total_length / 5.0)) + 1):
		var distance: float = minf(i * 5.0, total_length)
		var sample: Dictionary = at_distance(distance)
		var previous_sample: Dictionary = at_distance(maxf(0.0, distance - 5.0))
		if i > 0:
			var mid: Dictionary = at_distance(maxf(0.0, distance - 2.5))
			heading += float(mid.curvature) * 0.004 * 5.0
			position += Vector3(sin(heading), 0, -cos(heading)) * 5.0
			var elevation_delta: float = float(sample.elevation) - float(previous_sample.elevation)
			if sample.id != previous_sample.id:
				elevation_delta = 0.0
			last_elevation += elevation_delta
		position.y = last_elevation
		positions.append(position)
		headings.append(heading)
	revision += 1
	return true


func section_index(distance: float) -> int:
	var index: int = 0
	for i: int in range(starts.size()):
		if distance >= starts[i]:
			index = i
	return index


func at_distance(distance: float) -> Dictionary:
	var index: int = section_index(distance)
	return sample(path[index], distance - starts[index])


func presentation_sample(distance: float) -> Dictionary:
	var result: Dictionary = at_distance(distance)
	if not result.split.is_empty():
		return result
	for index: int in range(1, starts.size()):
		var boundary: float = starts[index]
		if absf(distance - boundary) > PRESENTATION_TRANSITION:
			continue
		var previous: Dictionary = sample(path[index - 1], float(sections[path[index - 1]].length))
		var next: Dictionary = sample(path[index], 0)
		var blend: float = smoothstep(boundary - PRESENTATION_TRANSITION, boundary + PRESENTATION_TRANSITION, distance)
		for key: String in ["half_width", "lanes", "shoulder"]:
			result[key] = lerpf(float(previous[key]), float(next[key]), blend)
		break
	return result


func sample(id: String, distance: float) -> Dictionary:
	var section: Dictionary = sections[id]
	var t: float = clampf(distance / float(section.length), 0.0, 1.0)
	var curve: Dictionary = section.curve
	var curvature: float = (lerpf(float(curve.entry), float(curve.apex), smoothstep(0, 0.5, t))
		if t < 0.5 else lerpf(float(curve.apex), float(curve.exit), smoothstep(0.5, 1, t)))
	var elevation: float = height(section, distance)
	var lower: float = maxf(0, distance - 1.0)
	var upper: float = minf(float(section.length), distance + 1.0)
	var grade: float = ((height(section, upper) - height(section, lower)) / (upper - lower)
		if upper > lower else 0.0)
	if id == start_id:
		var blend: float = smoothstep(40, 160, distance)
		var normalized: float = clampf((distance - 40.0) / 120.0, 0, 1)
		var derivative: float = 6.0 * normalized * (1.0 - normalized) / 120.0
		var delta: float = elevation - float(section.elevation.startMeters)
		elevation = float(section.elevation.startMeters) + delta * blend
		grade = grade * blend + delta * derivative
		curvature *= blend
	var cross: Dictionary = split_cross(id, distance)
	return {"id": id, "distance": distance, "curvature": curvature, "elevation": elevation,
		"grade": grade, "half_width": float(cross.half_width) if not cross.is_empty()
			else float(section.lanes.count) * float(section.lanes.width) / 2.0,
		"lanes": int(section.lanes.count), "lane_width": float(section.lanes.width),
		"shoulder": float(section.lanes.shoulderWidth), "environment": section.environment,
		"split": cross}


func split_cross(id: String, distance: float, include_endpoints: bool = false) -> Dictionary:
	if id not in ["coast-solar-sweep", "skyline-1"]:
		return {}
	var length: float = float(sections[id].length)
	if length < 400:
		return {}
	var entrance: float = length * 0.2
	var transition: float = length * 0.12
	var merge_start: float = length * 0.7
	var merge_end: float = merge_start + transition
	if not include_endpoints and (distance <= entrance or distance >= merge_end):
		return {}
	var a: float = clampf((distance - entrance) / transition, 0, 1)
	var b: float = clampf((distance - merge_start) / transition, 0, 1)
	var blend: float = a * a * a * (a * (6 * a - 15) + 10) \
		* (1 - b * b * b * (b * (6 * b - 15) + 10))
	var width: float = float(sections[id].lanes.width)
	var narrow_count: int = 1 if id == "skyline-1" else 2
	var wide: float = width * 1.5
	var narrow: float = width * narrow_count / 2.0
	var progress: float = clampf((distance - entrance) / (merge_end - entrance), 0, 1)
	var sweep: float = pow(sin(PI * progress), 4)
	var chicane: float = pow(sin(2 * PI * progress), 3)
	var left_center: float = -(wide + 26 + 12 * sweep) * blend
	var right_center: float = (narrow + 42 + 14 * chicane) * blend
	var right_half: float = lerpf(wide, narrow, blend)
	return {"left_center": left_center, "right_center": right_center,
		"left_half": wide, "right_half": right_half, "narrow_count": narrow_count,
		"left_elevation": -1.2 * sweep * blend,
		"right_elevation": 5 * pow(sin(PI * progress), 2) * blend,
		"half_width": maxf(-left_center + wide, right_center + right_half)}


func split_component(id: String, distance: float, side: int, key: String) -> float:
	var cross: Dictionary = split_cross(id, distance, true)
	if cross.is_empty():
		return 0.0
	return float(cross[("left_" if side < 0 else "right_") + key])


func split_heading(id: String, distance: float, side: int) -> float:
	return atan(split_component(id, distance + 0.5, side, "center")
		- split_component(id, distance - 0.5, side, "center"))


func split_path(id: String, distance: float, side: int) -> Dictionary:
	var cross: Dictionary = split_cross(id, distance)
	if cross.is_empty() or side == 0:
		return {}
	var heading: float = split_heading(id, distance, side)
	var grade: float = split_component(id, distance + 0.5, side, "elevation") \
		- split_component(id, distance - 0.5, side, "elevation")
	return {"center": split_component(id, distance, side, "center"),
		"half_width": split_component(id, distance, side, "half"),
		"elevation": split_component(id, distance, side, "elevation"),
		"heading": heading, "grade": grade,
		"curvature": (split_heading(id, distance + 0.5, side) - split_heading(id, distance - 0.5, side)) / 0.004,
		"distance_scale": sqrt(1 + tan(heading) * tan(heading) + grade * grade)}


func driving_sample(id: String, distance: float, side: int) -> Dictionary:
	var result: Dictionary = sample(id, distance)
	var path_sample: Dictionary = split_path(id, distance, side)
	if not path_sample.is_empty():
		result.curvature = clampf(float(result.curvature) + float(path_sample.curvature), -0.85, 0.85)
		result.grade = (float(result.grade) + float(path_sample.grade)) / float(path_sample.distance_scale)
		result.elevation = float(result.elevation) + float(path_sample.elevation)
		result.half_width = path_sample.half_width
	return result


func lane_centers(id: String, distance: float) -> PackedFloat64Array:
	var cross: Dictionary = split_cross(id, distance)
	var result: PackedFloat64Array = []
	if cross.is_empty():
		var count: int = int(sections[id].lanes.count)
		for lane: int in range(count):
			result.append((lane + 0.5) / count * 2 - 1)
	else:
		for side: int in [-1, 1]:
			var count: int = 3 if side < 0 else int(cross.narrow_count)
			var center: float = float(cross.left_center if side < 0 else cross.right_center)
			var half: float = float(cross.left_half if side < 0 else cross.right_half)
			for lane: int in range(count):
				result.append((center - half + (lane + 0.5) * half * 2 / count) / float(cross.half_width))
	return result


func actor_frame(distance: float, lateral: float, side: int = 0) -> Transform3D:
	var sample_data: Dictionary = at_distance(distance)
	var cross: Dictionary = sample_data.split
	if cross.is_empty():
		return frame(distance, lateral)
	var meters: float = lateral * float(cross.half_width)
	if side == 0:
		side = -1 if absf(meters - float(cross.left_center)) < absf(meters - float(cross.right_center)) else 1
	var result: Transform3D = branch_frame(distance, side)
	var center: float = float(cross.left_center if side < 0 else cross.right_center)
	result.origin += result.basis.x * (meters - center)
	return result


func branch_frame(distance: float, side: int) -> Transform3D:
	var base: Transform3D = frame(distance)
	var sample_data: Dictionary = at_distance(distance)
	var path_sample: Dictionary = split_path(str(sample_data.id), float(sample_data.distance), side)
	if path_sample.is_empty():
		return base
	base.origin += base.basis.x * float(path_sample.center) + Vector3.UP * float(path_sample.elevation)
	var yaw: float = atan2(-base.basis.x.z, base.basis.x.x) - float(path_sample.heading)
	base.basis = Basis(Vector3.UP, yaw)
	base.basis = base.basis.rotated(base.basis.x, atan(float(sample_data.grade) + float(path_sample.grade)))
	return base


func height(section: Dictionary, distance: float) -> float:
	var t: float = clampf(distance / float(section.length), 0.0, 1.0)
	var elevation: Dictionary = section.elevation
	var start: float = float(elevation.startMeters)
	var end: float = float(elevation.endMeters)
	if not elevation.has("crestMeters"):
		return lerpf(start, end, smoothstep(0, 1, t))
	var control: float = 2.0 * float(elevation.crestMeters) - 0.5 * (start + end)
	return (1 - t) * (1 - t) * start + 2 * (1 - t) * t * control + t * t * end


func frame(distance: float, lateral: float = 0.0) -> Transform3D:
	var bounded: float = clampf(distance, 0, total_length)
	var index: int = mini(int(bounded / 5.0), positions.size() - 2)
	var alpha: float = clampf((bounded - index * 5.0) / 5.0, 0, 1)
	var center: Vector3 = positions[index].lerp(positions[index + 1], alpha)
	var heading: float = lerpf(headings[index], headings[index + 1], alpha)
	var right: Vector3 = Vector3(cos(heading), 0, sin(heading))
	center += right * lateral * float(presentation_sample(bounded).half_width)
	if distance != bounded:
		center += Vector3(sin(heading), 0, -cos(heading)) * (distance - bounded)
	var basis: Basis = Basis(Vector3.UP, -heading)
	var lower: Dictionary = at_distance(index * 5.0)
	var upper: Dictionary = at_distance(minf(total_length, (index + 1) * 5.0))
	var pitch: float = lerpf(atan(float(lower.grade)), atan(float(upper.grade)), alpha)
	basis = basis.rotated(right, pitch if distance == bounded else 0.0)
	return Transform3D(basis, center)

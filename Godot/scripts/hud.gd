class_name RacerHUD
extends Control

var simulation: RacerSimulation
var settings: Dictionary
var message: String = ""
var message_remaining: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	accessibility_name = "Race status"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_feedback(text: String) -> void:
	message = text
	message_remaining = 2.0


func _process(delta: float) -> void:
	if simulation != null and simulation.phase != "paused":
		message_remaining = maxf(0, message_remaining - delta)
		accessibility_description = "%d seconds remaining. Speed %d kilometers per hour. Score %d. Boost %d percent." % [
			ceili(simulation.remaining), roundi(simulation.speed), roundi(simulation.score),
			roundi(simulation.boost / float(simulation.config.capacity) * 100)]
	queue_redraw()


func panel(rect: Rect2, color: Color) -> void:
	var p: Vector2 = rect.position
	var s: Vector2 = rect.size
	var cut: float = 9
	var vertices: PackedVector2Array = PackedVector2Array([
		p + Vector2(cut, 0), p + Vector2(s.x - cut, 0), p + Vector2(s.x, cut),
		p + s - Vector2(0, cut), p + s - Vector2(cut, 0), p + Vector2(cut, s.y),
		p + Vector2(0, s.y - cut), p + Vector2(0, cut)])
	draw_colored_polygon(vertices, Color(0.01, 0.0, 0.025, 0.94 if settings.high_contrast else 0.7))
	vertices.append(vertices[0])
	draw_polyline(vertices, color, 1.2, true)


func text(value: String, position: Vector2, font_size: int, color: Color, width: float = -1) -> void:
	draw_string(ThemeDB.fallback_font, position, value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)


func _draw() -> void:
	if simulation == null:
		return
	var cyan: Color = Color("#00efff")
	var pink: Color = Color("#ff2d95")
	if int(settings.color_palette) == 1:
		cyan = Color("#168bff")
		pink = Color("#ff8a00")
	elif int(settings.color_palette) == 2:
		cyan = Color("#34d399")
	var inset: float = 12
	var timer_rect: Rect2 = Rect2(inset, 12, 156, 76)
	panel(timer_rect, cyan)
	text("TIME", timer_rect.position + Vector2(10, 19), 13, cyan)
	var seconds: int = ceili(simulation.remaining)
	var time_label: String = "%d:%02d:%02d" % [int(seconds / 3600.0), int(seconds / 60.0) % 60, seconds % 60]
	text(time_label, timer_rect.position + Vector2(10, 61), 35, cyan)
	var speed_rect: Rect2 = Rect2(size.x - 258, 12, 192, 70)
	panel(speed_rect, cyan)
	text("SPEED", speed_rect.position + Vector2(10, 27), 12, cyan)
	text("%3d" % roundi(simulation.speed), speed_rect.position + Vector2(68, 37), 35, cyan)
	text("km/h", speed_rect.position + Vector2(150, 34), 12, Color.WHITE)
	text("BOOST", speed_rect.position + Vector2(12, 58), 12, pink)
	var bar: Rect2 = Rect2(speed_rect.position + Vector2(60, 48), Vector2(118, 8))
	draw_rect(bar, Color(pink, 0.15))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * simulation.boost / float(simulation.config.capacity), 8)), pink)
	var stage: Dictionary = simulation.track.sections[simulation.stage_id]
	var stage_text: String = simulation.stage_id.replace("-", " ").to_upper()
	var score_rect: Rect2 = Rect2(190, 12, maxf(200, size.x - 470), 34)
	panel(score_rect, cyan)
	text("S%d  %s" % [simulation.committed.size() + 1, stage_text], score_rect.position + Vector2(9, 23), 12, pink,
		score_rect.size.x * 0.62)
	text("%07d" % roundi(simulation.score), score_rect.position + Vector2(score_rect.size.x - 92, 24), 20, cyan)
	panel(Rect2(inset, 96, 114, 74), cyan)
	var path_points: PackedVector2Array = PackedVector2Array()
	for i: int in range(25):
		var progress: float = i / 24.0
		path_points.append(Vector2(inset + 18 + progress * 74, 155 - progress * 42 + sin(progress * 6) * 8))
	draw_polyline(path_points, cyan, 2, true)
	var fraction: float = clampf(simulation.distance / simulation.track.total_length, 0, 1)
	draw_circle(path_points[mini(24, int(fraction * 24))], 4, Color("#ffe45e"))
	text("CP", Vector2(inset + 52, 128), 10, pink)
	var left: float = maxf(210, size.x * 0.23)
	var right: float = size.x - maxf(250, size.x * 0.25)
	if right > left:
		draw_line(Vector2(left, size.y - 24), Vector2(right, size.y - 24), Color(cyan, 0.6), 1)
		for checkpoint: int in range(5):
			draw_arc(Vector2(lerpf(left, right, checkpoint / 4.0), size.y - 24), 5, 0, TAU, 24, cyan, 1, true)
		draw_circle(Vector2(lerpf(left, right, fraction), size.y - 24), 4, Color("#ffe45e"))
	if simulation.phase == "countdown":
		var count: String = str(ceili(simulation.countdown))
		text(count, size / 2 - Vector2(24, -20), 80, cyan)
	elif message_remaining > 0:
		var width: float = ThemeDB.fallback_font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		text(message, Vector2((size.x - width) / 2, size.y * 0.27), 18, Color("#ffe45e"))
	elif simulation.offroad:
		text("OFF ROAD", Vector2(size.x / 2 - 60, size.y * 0.27), 18, Color("#ff8a00"))
	if bool(settings.large_hud):
		text("%ds LEFT  |  %d km/h  |  %d POINTS" % [seconds, roundi(simulation.speed), roundi(simulation.score)],
			Vector2(size.x / 2 - 180, size.y * 0.45), 24, Color.WHITE)
	if simulation.combo > 1:
		text("COMBO x%.2f" % minf(4, 1 + int(simulation.combo / 2.0) * 0.25),
			Vector2(size.x / 2 - 50, 68), 14, pink)
	if stage.links.size() > 1 and float(stage.length) - (simulation.distance - simulation.stage_start) < 500:
		var next: String = "NEXT: " + simulation.next_stage_id().replace("-", " ").to_upper()
		var width: float = ThemeDB.fallback_font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		text(next, Vector2((size.x - width) / 2, 95), 16, cyan)

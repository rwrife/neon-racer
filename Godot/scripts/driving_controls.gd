class_name RacerDrivingControls
extends Control

var steering: float = 0.0
var throttle: bool = false
var brake: bool = false
var boost: bool = false
var pointers: Dictionary = {}
var pointer_positions: Dictionary = {}
var semantic_buttons: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	accessibility_name = "Driving controls"
	accessibility_description = "Steering, brake, boost, and throttle. Activate a labeled control to hold or release it."
	for action: String in ["left", "right", "brake", "boost", "throttle"]:
		var node: Button = Button.new()
		node.text = action.capitalize()
		node.accessibility_name = "Steer " + action if action in ["left", "right"] else "Go" if action == "throttle" else action.capitalize()
		node.accessibility_description = "Activate to hold or release this driving control."
		node.toggle_mode = true
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.self_modulate.a = 0
		node.toggled.connect(func(held: bool) -> void:
			if action == "left" and held:
				semantic_buttons.right.set_pressed_no_signal(false)
			elif action == "right" and held:
				semantic_buttons.left.set_pressed_no_signal(false)
			update_values())
		node.focus_entered.connect(queue_redraw)
		node.focus_exited.connect(queue_redraw)
		add_child(node)
		semantic_buttons[action] = node
	resized.connect(layout_semantics)
	layout_semantics()


func layout_semantics() -> void:
	for action: String in semantic_buttons:
		var node: Button = semantic_buttons[action]
		if action in ["left", "right"]:
			var rect: Rect2 = steering_rect()
			node.position = rect.position + (Vector2(rect.size.x / 2, 0) if action == "right" else Vector2.ZERO)
			node.size = Vector2(rect.size.x / 2, rect.size.y)
		else:
			node.position = action_center(action) - Vector2(36, 36)
			node.size = Vector2(72, 72)


func release_all() -> void:
	pointers.clear()
	pointer_positions.clear()
	for node: Button in semantic_buttons.values():
		node.set_pressed_no_signal(false)
	update_values()


func steering_rect() -> Rect2:
	return Rect2(22, size.y - 104, clampf(size.x * 0.34, 220, 340), 86)


func action_center(action: String) -> Vector2:
	var index: int = ["brake", "boost", "throttle"].find(action)
	return Vector2(size.x - 22 - 36 - (2 - index) * 82, size.y - 54)


func hit(position: Vector2) -> String:
	if steering_rect().has_point(position):
		return "steering"
	for action: String in ["brake", "boost", "throttle"]:
		if position.distance_to(action_center(action)) <= 36:
			return action
	return ""


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var id: int = -1
	var position: Vector2
	var pressed: bool = false
	var released: bool = false
	var motion: bool = false
	if event is InputEventScreenTouch:
		id = event.index
		position = event.position - global_position
		pressed = event.pressed
		released = not event.pressed or event.canceled
	elif event is InputEventScreenDrag:
		id = event.index
		position = event.position - global_position
		motion = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		position = event.position - global_position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion:
		position = event.position - global_position
		motion = true
	else:
		return
	if released and pointers.has(id):
		pointers.erase(id)
		pointer_positions.erase(id)
	elif pressed:
		var action: String = hit(position)
		if action.is_empty():
			return
		pointers[id] = action
		pointer_positions[id] = position
	elif motion and pointers.has(id):
		pointer_positions[id] = position
	else:
		return
	update_values()
	get_viewport().set_input_as_handled()


func update_values() -> void:
	throttle = semantic_buttons.has("throttle") and semantic_buttons.throttle.button_pressed
	brake = semantic_buttons.has("brake") and semantic_buttons.brake.button_pressed
	boost = semantic_buttons.has("boost") and semantic_buttons.boost.button_pressed
	steering = 0
	if semantic_buttons.has("left") and semantic_buttons.left.button_pressed:
		steering = -1
	elif semantic_buttons.has("right") and semantic_buttons.right.button_pressed:
		steering = 1
	for id: int in pointers:
		match str(pointers[id]):
			"steering":
				var rect: Rect2 = steering_rect()
				steering = clampf((float(pointer_positions[id].x) - rect.position.x) / rect.size.x * 2 - 1, -1, 1)
			"throttle": throttle = true
			"brake": brake = true
			"boost": boost = true
	queue_redraw()


func _draw() -> void:
	var cyan: Color = Color("#22d3ee")
	var rect: Rect2 = steering_rect()
	var panel: StyleBoxFlat = StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0.22)
	panel.border_color = Color(cyan, 0.48)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(26)
	draw_style_box(panel, rect)
	draw_line(rect.get_center() - Vector2(0, 42), rect.get_center() + Vector2(0, 42), Color(1, 1, 1, 0.1))
	var font: Font = ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(rect.size.x * 0.23 - 10, 53), "<<", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1, 0.58))
	draw_string(font, rect.position + Vector2(rect.size.x * 0.77 - 10, 53), ">>", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1, 0.58))
	draw_circle(rect.get_center() + Vector2(steering * (rect.size.x / 2 - 24), 0), 7, Color(1, 1, 1, 0.78))
	for action: String in semantic_buttons:
		var node: Button = semantic_buttons[action]
		if node.has_focus():
			if action in ["left", "right"]:
				draw_rect(Rect2(node.position, node.size), Color.WHITE, false, 2)
			else:
				draw_arc(action_center(action), 39, 0, TAU, 64, Color.WHITE, 2, true)
	var colors: Array[Color] = [Color("#ff8a00"), cyan, Color("#ff2d95")]
	for index: int in range(3):
		var action: String = ["brake", "boost", "throttle"][index]
		var held: bool = brake if index == 0 else boost if index == 1 else throttle
		var center: Vector2 = action_center(action)
		draw_circle(center, 36, Color(colors[index], 0.55) if held else Color(0, 0, 0, 0.22))
		draw_arc(center, 36, 0, TAU, 64, Color(colors[index], 0.75), 1.2, true)
		if index == 0:
			draw_rect(Rect2(center - Vector2(8, 16), Vector2(16, 16)), Color("#cccccc"))
		elif index == 1:
			draw_colored_polygon(PackedVector2Array([center + Vector2(1, -23), center + Vector2(-9, -7),
				center + Vector2(-1, -7), center + Vector2(-4, 3),
				center + Vector2(10, -14), center + Vector2(2, -14)]), Color.WHITE)
		else:
			draw_line(center + Vector2(0, 1), center + Vector2(0, -20), Color.WHITE, 3, true)
			draw_line(center + Vector2(0, -20), center + Vector2(-8, -12), Color.WHITE, 3, true)
			draw_line(center + Vector2(0, -20), center + Vector2(8, -12), Color.WHITE, 3, true)
		var label: String = ["BRAKE", "BOOST", "GO"][index]
		draw_string(font, center + Vector2(-28, 22), label, HORIZONTAL_ALIGNMENT_CENTER, 56, 11, Color("#cccccc"))

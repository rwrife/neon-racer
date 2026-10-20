extends Node

const DEFAULT_BINDINGS: Dictionary = {
	"steer_left": KEY_LEFT, "steer_right": KEY_RIGHT, "throttle": KEY_UP, "brake": KEY_DOWN,
	"boost": KEY_SPACE, "pause": KEY_ESCAPE, "ui_accept": KEY_ENTER, "ui_cancel": KEY_ESCAPE,
	"ui_up": KEY_UP, "ui_down": KEY_DOWN, "ui_left": KEY_LEFT, "ui_right": KEY_RIGHT,
}
var store: RacerProfileStore = RacerProfileStore.new()
var audio: RacerAudio = RacerAudio.new()
var simulation: RacerSimulation
var world: RacerWorld
var layer: CanvasLayer = CanvasLayer.new()
var ui: Control = Control.new()
var safe_ui: MarginContainer = MarginContainer.new()
var screen: Control = Control.new()
var overlay: Control = Control.new()
var controls: RacerDrivingControls
var hud: RacerHUD
var state: String = "menu"
var pause_button: Button
var capture_action: String = ""
var capture_button: Button
var recovery: Dictionary = {}
var recovery_path: String = "user://run-recovery.json"
var recovery_elapsed: float = 0.0
var error_label: Label
var result_unlocks: Array[String] = []
var previous_best: int = 0
var course_choices: Array[String] = []


func _ready() -> void:
	add_child(audio)
	add_child(layer)
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(safe_ui)
	safe_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_theme()
	configure_input()
	if not store.load_profile():
		show_profile_recovery()
		return
	configure_input()
	audio.apply_preferences(store.profile.settings)
	audio.show_menu()
	show_menu()
	load_recovery()
	get_viewport().size_changed.connect(update_safe_area)
	update_safe_area()
	if OS.get_cmdline_user_args().has("--race"):
		show_course()


func apply_theme() -> void:
	var theme: Theme = Theme.new()
	theme.default_font_size = 14
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color("#151323")
	normal.border_color = Color("#274653")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	theme.set_stylebox("normal", "Button", normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color("#153748")
	hover.border_color = Color("#22d3ee")
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", hover)
	var focus: StyleBoxFlat = StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("#22d3ee")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(12)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", Color("#22d3ee"))
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	ui.theme = theme


func update_safe_area() -> void:
	var inset_x: int = 0
	var inset_y: int = 0
	if OS.get_name() in ["iOS", "Android"]:
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var display_size: Vector2i = DisplayServer.screen_get_size()
		if display_size.x > 0 and display_size.y > 0:
			inset_x = ceili(maxf(safe.position.x, display_size.x - safe.end.x) *
				get_viewport().get_visible_rect().size.x / display_size.x)
			inset_y = ceili(maxf(safe.position.y, display_size.y - safe.end.y) *
				get_viewport().get_visible_rect().size.y / display_size.y)
	for side: String in ["left", "right"]:
		safe_ui.add_theme_constant_override("margin_" + side, inset_x)
	for side: String in ["top", "bottom"]:
		safe_ui.add_theme_constant_override("margin_" + side, inset_y)


func clear_children(parent: Node) -> void:
	if parent == overlay:
		set_screen_focus(true)
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func clear_screen() -> void:
	clear_children(screen)
	clear_children(safe_ui)
	clear_children(overlay)
	controls = null
	hud = null
	pause_button = null


func label(text: String, font_size: int = 14, color: Color = Color.WHITE) -> Label:
	var node: Label = Label.new()
	node.text = text
	node.accessibility_name = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node


func button(text: String, action: Callable, parent: Node, tint: Color = Color("#22d3ee")) -> Button:
	var node: Button = Button.new()
	node.text = text
	node.custom_minimum_size.y = 44
	node.add_theme_color_override("font_color", tint)
	node.pressed.connect(action)
	node.pressed.connect(func() -> void: audio.cue("confirm"))
	parent.add_child(node)
	return node


func background() -> void:
	var art: TextureRect = TextureRect.new()
	art.texture = preload("res://assets/title.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(art)


func show_menu() -> void:
	state = "menu"
	if world != null:
		world.queue_free()
		world = null
	simulation = null
	audio.show_menu()
	clear_screen()
	background()
	var bottom: VBoxContainer = VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 0)
	safe_ui.add_child(bottom)
	var center: CenterContainer = CenterContainer.new()
	bottom.add_child(center)
	var spacer: Control = Control.new()
	bottom.add_child(spacer)
	var update_spacing: Callable = func() -> void:
		spacer.custom_minimum_size.y = get_viewport().get_visible_rect().size.y * 0.05
	bottom.resized.connect(update_spacing)
	update_spacing.call()
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_corner_radius_all(28)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var race_button: Button = button("RACE", show_course, row, Color("#ff2d95"))
	race_button.custom_minimum_size.x = 180
	button("GARAGE", show_garage, row).custom_minimum_size.x = 180
	button("SETTINGS", show_settings, row).custom_minimum_size.x = 180
	race_button.grab_focus()


func sheet(title: String, done: Callable = show_menu) -> VBoxContainer:
	clear_screen()
	background()
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(shade)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 35)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	safe_ui.add_child(margin)
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("#090815")
	style.set_corner_radius_all(18)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title_label: Label = label(title, 22)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	button("Done", done, header)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	return content


func show_garage() -> void:
	state = "garage"
	var content: VBoxContainer = sheet("Garage")
	var cards: HBoxContainer = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	content.add_child(cards)
	for vehicle: Dictionary in RacerCatalog.VEHICLES:
		var card: VBoxContainer = VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.x = 230
		cards.add_child(card)
		var selected: bool = store.profile.vehicle == vehicle.id
		card.add_child(label(vehicle.name.to_upper(), 16, Color("#22d3ee") if selected else Color.WHITE))
		var preview: SubViewportContainer = SubViewportContainer.new()
		preview.custom_minimum_size = Vector2(200, 100)
		preview.stretch = true
		card.add_child(preview)
		var viewport: SubViewport = SubViewport.new()
		viewport.size = Vector2i(230, 100)
		viewport.own_world_3d = true
		viewport.transparent_bg = true
		preview.add_child(viewport)
		var colors: Dictionary = RacerCatalog.item(RacerCatalog.PALETTES,
			str(store.profile.palette) if selected else str(vehicle.palette))
		var car: Node3D = RacerWorld.make_car(Color(str(colors.primary)), Color(str(colors.secondary)))
		viewport.add_child(car)
		var camera: Camera3D = Camera3D.new()
		viewport.add_child(camera)
		camera.position = Vector3(4.5, 3.2, 6)
		camera.fov = 30
		camera.look_at(Vector3(0, 0.4, 0))
		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-40, -25, 0)
		light.light_energy = 2
		viewport.add_child(light)
		card.add_child(label(vehicle.tagline, 11))
		var config: Dictionary = RacerCatalog.configuration(str(vehicle.profile))
		card.add_child(label("SPEED %d   ACCEL %d   STEER %.2f" %
			[int(config.maximum_speed), int(config.acceleration), float(config.steering_rate)], 11))
		var available: bool = RacerCatalog.unlocked(vehicle, store.profile)
		var select: Button = button("SELECTED" if selected else "SELECT" if available else RacerCatalog.requirement(vehicle),
			func() -> void:
				store.profile.vehicle = vehicle.id
				store.profile.palette = vehicle.palette
				persist()
				show_garage(), card)
		select.disabled = not available
	content.add_child(label("SELECTED LOADOUT", 11, Color("#9995ab")))
	content.add_child(label("%s  /  %s  /  %s" % [
		RacerCatalog.item(RacerCatalog.VEHICLES, str(store.profile.vehicle)).name,
		RacerCatalog.item(RacerCatalog.PALETTES, str(store.profile.palette)).name,
		RacerCatalog.item(RacerCatalog.ROUTES, str(store.profile.route)).name], 13))
	button("MODIFY SELECTED CAR", show_customization, content)
	focus_first(content)


func show_customization() -> void:
	state = "customization"
	var content: VBoxContainer = sheet("Customize Selected Car", show_garage)
	content.add_child(label("PALETTE", 12, Color("#9995ab")))
	for colors: Dictionary in RacerCatalog.PALETTES:
		var available: bool = RacerCatalog.unlocked(colors, store.profile)
		var node: Button = button(("[SELECTED] " if store.profile.palette == colors.id else "")
			+ str(colors.name) + ("" if available else " - " + RacerCatalog.requirement(colors)),
			func() -> void:
				store.profile.palette = colors.id
				persist()
				show_customization(), content, Color(str(colors.primary)))
		node.disabled = not available
	content.add_child(label("ROUTE", 12, Color("#9995ab")))
	for route: Dictionary in RacerCatalog.ROUTES:
		var available: bool = RacerCatalog.unlocked(route, store.profile)
		var node: Button = button(("[SELECTED] " if store.profile.route == route.id else "")
			+ str(route.name) + " - " + str(route.subtitle)
			+ ("" if available else " - " + RacerCatalog.requirement(route)),
			func() -> void:
				store.profile.route = route.id
				persist()
				show_customization(), content)
		node.disabled = not available
		if store.profile.records.has(route.id):
			var record: Dictionary = store.profile.records[route.id]
			content.add_child(label("BEST %d  /  %.2fs" % [int(record.score), float(record.time)], 12))
	focus_first(content)


func setting_toggle(title: String, key: String, parent: Node) -> void:
	var toggle: CheckButton = CheckButton.new()
	toggle.text = title
	toggle.custom_minimum_size.y = 44
	toggle.button_pressed = bool(store.profile.settings[key])
	toggle.toggled.connect(func(value: bool) -> void:
		store.profile.settings[key] = value
		settings_changed())
	parent.add_child(toggle)


func setting_slider(title: String, key: String, parent: Node) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	var title_label: Label = label(title)
	title_label.custom_minimum_size.x = 190
	row.add_child(title_label)
	var slider: HSlider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value = float(store.profile.settings[key])
	slider.custom_minimum_size = Vector2(250, 44)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = title
	slider.accessibility_name = title
	slider.value_changed.connect(func(value: float) -> void:
		store.profile.settings[key] = value
		settings_changed())
	row.add_child(slider)


func setting_options(title: String, key: String, choices: Array[String], parent: Node) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	var title_label: Label = label(title)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	var options: OptionButton = OptionButton.new()
	options.custom_minimum_size = Vector2(220, 44)
	for choice: String in choices:
		options.add_item(choice)
	options.selected = int(store.profile.settings[key])
	options.item_selected.connect(func(index: int) -> void:
		store.profile.settings[key] = index
		settings_changed())
	row.add_child(options)


func show_settings() -> void:
	state = "settings"
	var content: VBoxContainer = sheet("Settings")
	content.add_child(label("AUDIO", 12, Color("#9995ab")))
	setting_slider("Music", "music", content)
	setting_toggle("Mute Music", "mute_music", content)
	setting_slider("Effects", "effects", content)
	setting_toggle("Mute Effects", "mute_effects", content)
	content.add_child(label("FEEDBACK", 12, Color("#9995ab")))
	setting_toggle("Haptics", "haptics", content)
	setting_slider("Haptic Intensity", "haptic_intensity", content)
	setting_options("Render Quality", "quality", ["Automatic", "Efficiency", "Balanced", "High"], content)
	content.add_child(label("Changes apply at the start of the next run.", 11, Color("#9995ab")))
	content.add_child(label("INPUT REMAPPING", 12, Color("#9995ab")))
	for action: String in DEFAULT_BINDINGS:
		var key: int = int(store.profile.settings.bindings.get(action, DEFAULT_BINDINGS[action]))
		var mapping: Button = button(action.replace("_", " ").capitalize() + ": " + OS.get_keycode_string(key),
			func() -> void: pass, content)
		mapping.pressed.connect(func() -> void:
			capture_action = action
			capture_button = mapping
			mapping.text = "Press a key (Escape cancels)")
	button("Reset Input Mapping", func() -> void:
		store.profile.settings.bindings.clear()
		configure_input()
		persist()
		show_settings(), content)
	button("Accessibility", show_accessibility, content)
	button("Driving Guide", func() -> void: show_guide(show_settings), content)
	button("Reset Player Data", func() -> void:
		confirm("Reset all player data?",
			"This clears scores, cars, routes, records, controls, and haptic settings. Audio and accessibility preferences are preserved.",
			func() -> void:
				if not store.reset():
					show_error(store.error_message)
					return
				clear_recovery()
				configure_input()
				settings_changed()
				show_settings()), content, Color("#ff5d75"))
	focus_first(content)


func show_accessibility() -> void:
	state = "accessibility"
	var content: VBoxContainer = sheet("Accessibility", show_settings)
	setting_toggle("Reduce Motion", "reduce_motion", content)
	setting_toggle("Reduce Flashes", "reduce_flashes", content)
	setting_toggle("High Contrast", "high_contrast", content)
	setting_toggle("Larger Race Display", "large_hud", content)
	setting_options("Color Palette", "color_palette",
		["Classic Neon", "Blue & Orange", "Magenta & Green"], content)
	var notice: Label = label("Custom controls support keyboard and gamepad navigation. iOS VoiceOver and system accessibility integration still require device signoff.", 12, Color("#aaa5bc"))
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(notice)
	focus_first(content)


func settings_changed() -> void:
	audio.apply_preferences(store.profile.settings)
	persist()


func persist() -> void:
	if not store.save():
		show_error(store.error_message)
	elif is_instance_valid(error_label):
		error_label.text = ""


func focus_first(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is BaseButton and not child.disabled:
			child.grab_focus()
			return true
		if focus_first(child):
			return true
	return false


func set_screen_focus(enabled: bool, node: Node = null) -> void:
	var target: Node = safe_ui if node == null else node
	for child: Node in target.get_children():
		if child is Control:
			if enabled and child.has_meta("modal_focus"):
				child.focus_mode = int(child.get_meta("modal_focus"))
				child.remove_meta("modal_focus")
			elif not enabled and child.focus_mode != Control.FOCUS_NONE:
				child.set_meta("modal_focus", child.focus_mode)
				child.focus_mode = Control.FOCUS_NONE
		set_screen_focus(enabled, child)


func show_course() -> void:
	state = "course"
	var content: VBoxContainer = sheet("Choose your course")
	var vehicle: Dictionary = RacerCatalog.item(RacerCatalog.VEHICLES, str(store.profile.vehicle))
	var track: RacerTrack = RacerTrack.new(str(store.profile.route), str(vehicle.profile), course_choices)
	content.add_child(label(RacerCatalog.item(RacerCatalog.ROUTES, str(store.profile.route)).name.to_upper(),
		20, Color("#ff2d95")))
	var description: Label = label("Choose before starting. The complete course is prepared before the countdown; checkpoints never replace the road ahead.")
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)
	for id: String in track.path:
		var stage: Dictionary = track.sections[id]
		if stage.links.size() < 2:
			continue
		content.add_child(label("AFTER " + id.replace("-", " ").to_upper(), 14, Color("#22d3ee")))
		var row: HBoxContainer = HBoxContainer.new()
		content.add_child(row)
		for link: Dictionary in stage.links:
			var destination: String = str(link.destinationSectionID)
			button(("[SELECTED] " if track.path.has(destination) else "") + destination.replace("-", " ").to_upper(),
				func() -> void:
					for option: Dictionary in stage.links:
						course_choices.erase(str(option.destinationSectionID))
					course_choices.append(destination)
					show_course(), row)
	var itinerary: Label = label("  >  ".join(track.path).replace("-", " ").to_upper(), 13)
	itinerary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(itinerary)
	content.add_child(label("%.1f km  /  %d stages  /  course locked at start" % [track.total_length / 1000, track.path.size()]))
	button("PREPARE & RACE", start_race, content, Color("#ff2d95")).grab_focus()


func start_race() -> void:
	if state == "loading":
		return
	if world != null:
		world.queue_free()
		world = null
	clear_screen()
	state = "loading"
	background()
	var loading: VBoxContainer = modal("PREPARING COURSE", "Building the entire road, tunnels, scenery, and traffic pool before the countdown.")
	var progress: ProgressBar = ProgressBar.new()
	progress.max_value = 1
	loading.add_child(progress)
	var vehicle: Dictionary = RacerCatalog.item(RacerCatalog.VEHICLES, str(store.profile.vehicle))
	simulation = RacerSimulation.new(str(store.profile.route), str(vehicle.profile), 1, course_choices)
	course_choices.assign(simulation.track.path)
	world = RacerWorld.new()
	add_child(world)
	world.setup(simulation, store.profile.settings.duplicate(true),
		RacerCatalog.item(RacerCatalog.PALETTES, str(store.profile.palette)))
	await world.prepare_level(func(value: float) -> void: progress.value = value)
	clear_screen()
	state = "race"
	hud = RacerHUD.new()
	hud.simulation = simulation
	hud.settings = store.profile.settings
	safe_ui.add_child(hud)
	controls = RacerDrivingControls.new()
	safe_ui.add_child(controls)
	pause_button = Button.new()
	pause_button.text = "II"
	pause_button.custom_minimum_size = Vector2(44, 44)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.offset_left = -58
	pause_button.offset_right = -14
	pause_button.offset_top = 12
	pause_button.offset_bottom = 56
	pause_button.tooltip_text = "Pause race"
	pause_button.accessibility_name = "Pause race"
	pause_button.accessibility_description = "Opens resume, restart, and title controls."
	var pause_style: StyleBoxFlat = StyleBoxFlat.new()
	pause_style.bg_color = Color(0, 0, 0, 0.42)
	pause_style.border_color = Color("#22d3ee")
	pause_style.set_border_width_all(1)
	pause_style.set_corner_radius_all(44)
	pause_button.add_theme_stylebox_override("normal", pause_style)
	pause_button.pressed.connect(show_pause)
	# Keep the pause button anchored rather than managed by MarginContainer.
	hud.add_child(pause_button)
	simulation.feedback.connect(race_feedback)
	simulation.completed.connect(show_results)
	previous_best = int(store.profile.best)
	audio.start_race(simulation)
	recovery_elapsed = 0.0
	if not bool(store.profile.tutorial):
		simulation.set_paused(true)
		show_guide(func() -> void:
			store.profile.tutorial = true
			persist()
			clear_children(overlay)
			simulation.set_paused(false))
	elif DisplayServer.get_name() != "headless" and not get_window().has_focus():
		show_pause()


func race_feedback(text: String) -> void:
	if hud != null:
		hud.show_feedback(text)
	if text == "CRASH!":
		audio.cue("crash")
	elif text == "NEAR MISS!":
		audio.cue("near_miss")
	elif text == "OVERTAKE!":
		audio.cue("pass")
	elif text.begins_with("CHECKPOINT"):
		audio.intense = true
		audio.cue("checkpoint")
	if bool(store.profile.settings.haptics) and OS.get_name() in ["iOS", "Android"]:
		if text == "CRASH!" or text.begins_with("CHECKPOINT") or text == "GO!":
			Input.vibrate_handheld(80, float(store.profile.settings.haptic_intensity))


func _process(delta: float) -> void:
	if state != "race" or simulation == null:
		return
	var steer: float = Input.get_axis("steer_left", "steer_right")
	if absf(controls.steering) > 0.01:
		steer = controls.steering
	var wants_boost: bool = Input.is_action_pressed("boost") or controls.boost
	var throttle: float = 1.0 if Input.is_action_pressed("throttle") or controls.throttle or wants_boost else 0.0
	var brake: float = 1.0 if Input.is_action_pressed("brake") or controls.brake else 0.0
	simulation.advance(delta, steer, throttle, brake, wants_boost)
	recovery_elapsed += delta
	if recovery_elapsed >= 3 and simulation.phase == "racing":
		recovery_elapsed = 0
		save_recovery()


func modal(title: String, description: String) -> VBoxContainer:
	clear_children(overlay)
	set_screen_focus(false)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.76)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = 520
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("#0b0a19")
	style.border_color = Color("#22d3ee")
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(label(title, 24, Color("#22d3ee")))
	if not description.is_empty():
		var body: Label = label(description)
		body.custom_minimum_size.x = 460
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(body)
	return column


func confirm(title: String, description: String, action: Callable) -> void:
	var column: VBoxContainer = modal(title, description)
	button("Confirm", func() -> void:
		clear_children(overlay)
		action.call(), column, Color("#ff5d75"))
	button("Cancel", func() -> void:
		clear_children(overlay)
		if state == "paused":
			show_pause(), column).grab_focus()


func show_guide(done: Callable) -> void:
	var column: VBoxContainer = modal("DRIVING GUIDE",
		"Drag the left steering pad. Hold GO to accelerate, BRAKE to slow down, and BOOST for extra speed.\n\nBrake-tap while steering hard at speed to drift. Pass close to traffic for near-miss points and boost. Choose your course before racing; either lane of the physical split roads remains driveable.\n\nKeyboard: A/D or arrows steer, W accelerates, S brakes, Space boosts, Escape pauses. Gamepad: left stick, right/left triggers, A boosts, Start pauses.")
	button("LET'S RACE" if simulation != null else "Done", done, column).grab_focus()


func show_pause() -> void:
	if simulation == null or simulation.phase in ["finished", "failed"]:
		return
	state = "paused"
	simulation.set_paused(true)
	controls.release_all()
	controls.hide()
	var column: VBoxContainer = modal("PAUSED", "")
	button("RESUME", func() -> void:
		clear_children(overlay)
		controls.show()
		simulation.set_paused(false)
		state = "race", column).grab_focus()
	button("RESTART", func() -> void:
		confirm("Restart race?", "The current run will be discarded.", start_race), column)
	button("TITLE", func() -> void:
		confirm("Return to title?", "The current run will be discarded.", func() -> void:
			if clear_recovery():
				show_menu()), column)
	save_recovery()


func show_results(success: bool) -> void:
	state = "results"
	controls.release_all()
	controls.hide()
	pause_button.hide()
	result_unlocks = store.record(simulation)
	persist()
	clear_recovery()
	audio.show_menu()
	audio.cue("finish" if success else "failure")
	var column: VBoxContainer = modal("FINISH!" if success else "RUN OVER", "")
	column.add_child(label(simulation.rank().to_upper() + " RANK", 18))
	column.add_child(label("%d" % roundi(simulation.score), 40))
	column.add_child(label("NEW BEST" if simulation.score > previous_best else "BEST %d" % previous_best, 14, Color("#ff2d95")))
	column.add_child(label("TIME %.2fs  /  DISTANCE %dm" % [simulation.elapsed, roundi(simulation.distance)]))
	var breakdown_text: String = ""
	for key: String in simulation.breakdown:
		breakdown_text += "%s %d   " % [key.to_upper(), roundi(float(simulation.breakdown[key]))]
	var breakdown_label: Label = label(breakdown_text, 11)
	breakdown_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(breakdown_label)
	if not result_unlocks.is_empty():
		column.add_child(label("UNLOCKED: " + ", ".join(result_unlocks), 12, Color("#ffe45e")))
	button("RETRY", start_race, column).grab_focus()
	button("TITLE", show_menu, column)


func show_error(message: String) -> void:
	push_error(message)
	# Errors remain visible without replacing the current modal or destroying its focus.
	if error_label == null or not is_instance_valid(error_label):
		error_label = label("", 14, Color("#ff7b8e"))
		error_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		error_label.offset_top = 2
		error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(error_label)
	error_label.text = message


func show_profile_recovery() -> void:
	var column: VBoxContainer = modal("PROFILE RECOVERY", store.error_message)
	button("RESET LOCAL PROFILE", func() -> void:
		if not store.reset(true):
			show_error(store.error_message)
			return
		configure_input()
		audio.apply_preferences(store.profile.settings)
		show_menu(), column, Color("#ff5d75")).grab_focus()


func save_recovery() -> void:
	if simulation == null or simulation.phase in ["finished", "failed", "countdown"]:
		return
	var data: Dictionary = {"version": 1, "vehicle": store.profile.vehicle,
		"palette": store.profile.palette, "route": store.profile.route, "score": roundi(simulation.score),
		"stage": simulation.committed.size() + 1, "course": simulation.track.path}
	var result: Error = RacerProfileStore.write_json(recovery_path, data)
	if result != OK:
		show_error("Run recovery not saved: " + error_string(result))


func load_recovery() -> void:
	if not FileAccess.file_exists(recovery_path):
		return
	var parser: JSON = JSON.new()
	var result: Error = parser.parse(FileAccess.get_file_as_string(recovery_path))
	if result != OK or not parser.data is Dictionary:
		show_error("The interrupted-run file is damaged. Discard it from run recovery.")
		show_run_recovery(false)
		return
	recovery = parser.data
	var version: Variant = recovery.get("version", 0)
	var valid: bool = (version is float or version is int) and float(version) == 1.0
	for key: String in ["vehicle", "palette", "route"]:
		valid = valid and recovery.get(key) is String and recovery.get(key) == store.profile[key]
	if valid and recovery.has("course"):
		var saved_course: Variant = recovery.course
		valid = saved_course is Array
		var choices: Array[String] = []
		if valid:
			for id: Variant in saved_course:
				if not id is String:
					valid = false
					break
				choices.append(id)
		if valid:
			var vehicle: Dictionary = RacerCatalog.item(RacerCatalog.VEHICLES, str(store.profile.vehicle))
			var track: RacerTrack = RacerTrack.new(str(store.profile.route), str(vehicle.profile), choices)
			valid = choices == track.path
	show_run_recovery(valid)


func show_run_recovery(valid: bool) -> void:
	var column: VBoxContainer = modal("RUN RECOVERY",
		"A race was interrupted. Resume restarts the route with the saved loadout; it does not restore mid-race position.")
	if valid:
		button("RESUME ROUTE", func() -> void:
			if clear_recovery():
				course_choices.assign(recovery.get("course", []))
				start_race(), column)
	button("DISCARD RUN", func() -> void:
		if clear_recovery():
			clear_children(overlay), column).grab_focus()


func clear_recovery() -> bool:
	if not FileAccess.file_exists(recovery_path):
		return true
	var result: Error = DirAccess.remove_absolute(recovery_path)
	if result != OK:
		show_error("Could not discard interrupted run: " + error_string(result))
		return false
	return true


func configure_input() -> void:
	for action: String in DEFAULT_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.18)
		InputMap.action_erase_events(action)
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = int(store.profile.settings.bindings.get(action, DEFAULT_BINDINGS[action]))
		InputMap.action_add_event(action, event)
	if store.profile.settings.bindings.is_empty():
		for pair: Array in [["steer_left", KEY_A], ["steer_right", KEY_D], ["throttle", KEY_W], ["brake", KEY_S], ["pause", KEY_P]]:
			var key: InputEventKey = InputEventKey.new()
			key.physical_keycode = int(pair[1])
			InputMap.action_add_event(str(pair[0]), key)
	for pair: Array in [["steer_left", JOY_AXIS_LEFT_X, -1.0], ["steer_right", JOY_AXIS_LEFT_X, 1.0],
			["throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0], ["brake", JOY_AXIS_TRIGGER_LEFT, 1.0],
			["ui_left", JOY_AXIS_LEFT_X, -1.0], ["ui_right", JOY_AXIS_LEFT_X, 1.0],
			["ui_up", JOY_AXIS_LEFT_Y, -1.0], ["ui_down", JOY_AXIS_LEFT_Y, 1.0]]:
		var axis: InputEventJoypadMotion = InputEventJoypadMotion.new()
		axis.axis = int(pair[1])
		axis.axis_value = float(pair[2])
		InputMap.action_add_event(str(pair[0]), axis)
	for pair: Array in [["boost", JOY_BUTTON_A], ["pause", JOY_BUTTON_START],
			["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B],
			["ui_left", JOY_BUTTON_DPAD_LEFT], ["ui_right", JOY_BUTTON_DPAD_RIGHT],
			["ui_up", JOY_BUTTON_DPAD_UP], ["ui_down", JOY_BUTTON_DPAD_DOWN]]:
		var gamepad_button: InputEventJoypadButton = InputEventJoypadButton.new()
		gamepad_button.button_index = int(pair[1])
		InputMap.action_add_event(str(pair[0]), gamepad_button)


func _input(event: InputEvent) -> void:
	if controls != null:
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			controls.modulate.a = 0.35
		elif event is InputEventScreenTouch or event is InputEventMouseButton:
			controls.modulate.a = 1.0
	if not capture_action.is_empty() and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode != KEY_ESCAPE:
			store.profile.settings.bindings[capture_action] = event.physical_keycode
			configure_input()
			persist()
		capture_action = ""
		show_settings()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if state == "race":
			show_pause()
		elif state == "paused":
			clear_children(overlay)
			controls.show()
			simulation.set_paused(false)
			state = "race"
		elif state in ["garage", "settings", "course"]:
			show_menu()
		elif state == "customization":
			show_garage()
		elif state == "accessibility":
			show_settings()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		if state == "race":
			show_pause()
		if controls != null:
			controls.release_all()

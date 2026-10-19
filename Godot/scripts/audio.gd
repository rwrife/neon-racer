class_name RacerAudio
extends Node

var music: AudioStreamPlayer = AudioStreamPlayer.new()
var stems: Array[AudioStreamPlayer] = []
var engines: Array[AudioStreamPlayer] = []
var ambience: Array[AudioStreamPlayer] = []
var tires: AudioStreamPlayer
var cues: Dictionary = {}
var cue_players: Array[AudioStreamPlayer] = []
var cue_cursor: int = 0
var settings: Dictionary
var simulation: RacerSimulation
var intense: bool = false
var crossfade: float = 0.0
var pitch: float = 0.72
var engine_gain: float = 0.0
var tire_gain: float = 0.0
var ambience_gain: float = 0.0
var application_active: bool = true


func _ready() -> void:
	add_child(music)
	if DisplayServer.get_name() == "headless":
		return
	initialize_bank()


func initialize_bank() -> void:
	var stream: AudioStreamMP3 = preload("res://assets/menu.mp3")
	stream.loop = true
	music.stream = stream
	for name: String in ["bass", "arpeggio", "pad", "drums", "pulse"]:
		stems.append(loop_player(name))
	for name: String in ["fundamental", "harmonics", "whine"]:
		engines.append(loop_player(name))
	for name: String in ["city", "coast", "desert", "tunnel"]:
		ambience.append(loop_player(name))
	tires = loop_player("tires")
	for name: String in ["confirm", "pass", "near_miss", "combo", "checkpoint", "boost", "crash", "finish", "failure"]:
		cues[name] = load("res://assets/audio/" + name + ".res")
	for i: int in range(4):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		cue_players.append(player)


func loop_player(name: String) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = load("res://assets/audio/" + name + ".res")
	player.volume_db = -80.0
	add_child(player)
	player.play()
	return player


func apply_preferences(preferences: Dictionary) -> void:
	settings = preferences


func show_menu() -> void:
	simulation = null
	if not music.playing and music.stream != null:
		music.play()


func start_race(race: RacerSimulation) -> void:
	simulation = race
	intense = false
	pitch = 0.72
	engine_gain = 0.0
	tire_gain = 0.0


func cue(name: String) -> void:
	if cue_players.is_empty() or not application_active or settings.is_empty():
		return
	var player: AudioStreamPlayer = cue_players[cue_cursor]
	cue_cursor = (cue_cursor + 1) % cue_players.size()
	player.stop()
	player.stream = cues[name]
	player.volume_db = gain_db(effects_gain() * (0.5 if name == "crash" else 0.35))
	player.play()


func effects_gain() -> float:
	return 0.0 if bool(settings.mute_effects) else float(settings.effects)


func gain_db(value: float) -> float:
	return linear_to_db(value) if value > 0.0001 else -80.0


func _process(delta: float) -> void:
	if stems.is_empty() or settings.is_empty():
		return
	var racing: bool = simulation != null
	var paused: bool = not application_active or (racing and simulation.phase == "paused")
	var mix: float = 1 - exp(-minf(delta, 0.25) / 0.075)
	crossfade = move_toward(crossfade, 1.0 if racing else 0.0, delta / 0.65)
	var music_gain: float = 0.0 if bool(settings.mute_music) or paused else float(settings.music)
	music.volume_db = gain_db(music_gain * (1 - crossfade) * 0.62)
	var gains: Array[float] = [0.42, 0.22, 0.7, 0.18, 0.82]
	var section_gain: float = 0.72
	var ratio: float = 0.0
	var boost: float = 0.0
	var drift: float = 0.0
	var offroad: float = 0.0
	var recovery: float = 0.0
	if racing:
		ratio = clampf(simulation.speed / float(simulation.config.maximum_speed), 0, 1)
		boost = 1.0 if simulation.boosting else 0.0
		drift = 1.0 if simulation.drifting else 0.0
		offroad = 1.0 if simulation.offroad else 0.0
		recovery = clampf(simulation.wipeout / maxf(simulation.wipeout_duration, 0.001), 0, 1)
		intense = intense or simulation.boosting
		if ratio > 0.08:
			gains.assign([0.95, 0.88, 0.82, 0.98, 0.36] if intense else [0.82, 0.55, 0.7, 0.72, 0.15])
			section_gain = 0.94 if intense else 0.82
	for i: int in range(stems.size()):
		stems[i].volume_db = gain_db(music_gain * crossfade * gains[i] * section_gain * 0.6)
	var vehicle_gain: float = effects_gain() if racing and not paused else 0.0
	var throttle: float = 1.0 if Input.is_action_pressed("throttle") or boost > 0 else 0.0
	pitch = lerpf(pitch, 0.72 + ratio * 0.9 + boost * 0.14 - recovery * 0.12, mix)
	engine_gain = lerpf(engine_gain, clampf(0.14 + ratio * 0.42 + throttle * 0.28 + boost * 0.12, 0, 0.9), mix)
	tire_gain = lerpf(tire_gain, clampf(drift * 0.7 + offroad * 0.42, 0, 0.72), mix)
	ambience_gain = lerpf(ambience_gain, clampf(0.12 + ratio * 0.32, 0, 0.5), mix)
	var engine_layers: Array[float] = [0.58 + throttle * 0.22 + recovery * 0.08,
		0.16 + ratio * 0.46 + throttle * 0.14, boost * 0.78]
	for i: int in range(engines.size()):
		engines[i].pitch_scale = pitch
		engines[i].volume_db = gain_db(vehicle_gain * engine_gain * engine_layers[i])
	tires.volume_db = gain_db(vehicle_gain * tire_gain * (0.48 + drift * 0.34 + offroad * 0.18))
	var environment_index: int = 0
	if racing:
		var id: String = str(simulation.track.sections[simulation.stage_id].environment)
		environment_index = 1 if id == "sunset-coast" else 2 if id in ["midnight-peaks", "ion-storm", "summit-core"] else 0
		if simulation.stage_id in ["city-axis-tunnel", "skyline-2"]:
			environment_index = 3
	for i: int in range(ambience.size()):
		var target: float = vehicle_gain * ambience_gain * 0.8 if i == environment_index else 0.0
		ambience[i].volume_db = gain_db(lerpf(db_to_linear(ambience[i].volume_db), target, 1 - exp(-delta / 0.45)))


func _exit_tree() -> void:
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			child.stop()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		application_active = false
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		application_active = true

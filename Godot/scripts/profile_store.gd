class_name RacerProfileStore
extends RefCounted

const SAVE_PATH: String = "user://profile.json"
var save_path: String = SAVE_PATH
var profile: Dictionary = default_profile()
var error_message: String = ""


func _init(path: String = SAVE_PATH) -> void:
	save_path = path


static func default_profile() -> Dictionary:
	return {"version": 1, "vehicle": "prototype-zero", "palette": "synthwave", "route": "neon-loop",
		"races": 0, "gold": 0, "best": 0, "records": {}, "tutorial": false,
		"settings": {"music": 0.72, "effects": 0.85, "mute_music": false, "mute_effects": false,
			"haptics": true, "haptic_intensity": 1.0, "reduce_motion": false,
			"reduce_flashes": false, "high_contrast": false, "large_hud": false,
			"color_palette": 0, "quality": 0, "bindings": {}}}


func load_profile() -> bool:
	if not FileAccess.file_exists(save_path):
		return true
	var parser: JSON = JSON.new()
	var text: String = FileAccess.get_file_as_string(save_path)
	if parser.parse(text) != OK or not valid_profile(parser.data):
		error_message = "The local profile is damaged or unsupported. Reset preserves a backup."
		return false
	profile = parser.data
	return true


func valid_profile(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var data: Dictionary = value
	for key: String in default_profile():
		if not data.has(key) or typeof(data[key]) != typeof(default_profile()[key]):
			# JSON represents both integer and fractional numbers as floats.
			if not (data.has(key) and data[key] is float and default_profile()[key] is int):
				return false
	if float(data.version) != 1.0:
		return false
	for pair: Array in [[RacerCatalog.VEHICLES, "vehicle"], [RacerCatalog.PALETTES, "palette"],
			[RacerCatalog.ROUTES, "route"]]:
		var found: bool = false
		for entry: Dictionary in pair[0]:
			if entry.id == data[pair[1]]:
				found = RacerCatalog.unlocked(entry, data)
		if not found:
			return false
	var defaults: Dictionary = default_profile().settings
	for key: String in defaults:
		if not data.settings.has(key):
			return false
		var setting: Variant = data.settings[key]
		if typeof(setting) != typeof(defaults[key]):
			if not (setting is float and defaults[key] is int):
				return false
	for key: String in ["music", "effects", "haptic_intensity"]:
		if not is_finite(float(data.settings[key])) or float(data.settings[key]) < 0 or float(data.settings[key]) > 1:
			return false
	for key: String in ["races", "gold", "best"]:
		if float(data[key]) < 0 or not is_finite(float(data[key])) or float(data[key]) != floor(float(data[key])):
			return false
	for key: String in data.records:
		var record: Variant = data.records[key]
		if not record is Dictionary or not record.has("score") or not record.has("time"):
			return false
		for field: String in ["score", "time"]:
			if not (record[field] is float or record[field] is int):
				return false
			if not is_finite(float(record[field])) or float(record[field]) < 0:
				return false
	for action: String in data.settings.bindings:
		var key: Variant = data.settings.bindings[action]
		if not (key is int or key is float) or not is_finite(float(key)) or float(key) != floor(float(key)) or int(key) <= 0:
			return false
	return (float(data.settings.color_palette) == floor(float(data.settings.color_palette))
		and float(data.settings.quality) == floor(float(data.settings.quality))
		and int(data.settings.color_palette) in range(3) and int(data.settings.quality) in range(4))


func save() -> bool:
	var result: Error = write_json(save_path, profile)
	if result != OK:
		error_message = "Profile not saved: " + error_string(result)
		return false
	error_message = ""
	return true


static func write_json(path: String, data: Dictionary) -> Error:
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var result: Error = file.get_error()
	file.close()
	if result == OK:
		result = DirAccess.rename_absolute(temporary, path)
	return result


func reset(preserve_damaged: bool = false) -> bool:
	if preserve_damaged and FileAccess.file_exists(save_path):
		var backup: String = save_path + ".damaged-%d" % Time.get_unix_time_from_system()
		var result: Error = DirAccess.rename_absolute(save_path, backup)
		if result != OK:
			error_message = "Could not preserve damaged profile: " + error_string(result)
			return false
	var settings: Dictionary = profile.settings.duplicate(true)
	profile = default_profile()
	for key: String in ["music", "effects", "mute_music", "mute_effects", "reduce_motion",
			"reduce_flashes", "high_contrast", "large_hud", "color_palette"]:
		profile.settings[key] = settings[key]
	return save()


func record(simulation: RacerSimulation) -> Array[String]:
	if simulation.phase != "finished":
		return []
	var previous_unlocks: Array[String] = unlocks()
	profile.races = int(profile.races) + 1
	profile.best = maxi(int(profile.best), roundi(simulation.score))
	if simulation.rank() == "gold":
		profile.gold = int(profile.gold) + 1
	var records: Dictionary = profile.records
	var old: Dictionary = records.get(profile.route, {"score": 0, "time": INF})
	records[profile.route] = {"score": maxi(int(old.score), roundi(simulation.score)),
		"time": minf(float(old.time), simulation.elapsed)}
	var added: Array[String] = []
	for id: String in unlocks():
		if not previous_unlocks.has(id):
			added.append(id)
	return added


func unlocks() -> Array[String]:
	var result: Array[String] = []
	for catalog: Array[Dictionary] in [RacerCatalog.VEHICLES, RacerCatalog.PALETTES, RacerCatalog.ROUTES]:
		for entry: Dictionary in catalog:
			if RacerCatalog.unlocked(entry, profile):
				result.append(str(entry.id))
	return result

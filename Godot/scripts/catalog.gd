class_name RacerCatalog
extends RefCounted

const VEHICLES: Array[Dictionary] = [
	{"id": "prototype-zero", "name": "Prototype Zero", "tagline": "Balanced street prototype",
		"profile": "standard", "palette": "synthwave", "requirement": "starter", "count": 0},
	{"id": "vector-sprint", "name": "Vector Sprint", "tagline": "Responsive precision chassis",
		"profile": "novice", "palette": "electric-blue", "requirement": "races", "count": 3},
	{"id": "apex-phantom", "name": "Apex Phantom", "tagline": "Maximum velocity, narrow margins",
		"profile": "expert", "palette": "arctic-white", "requirement": "gold", "count": 2},
]
const PALETTES: Array[Dictionary] = [
	{"id": "synthwave", "name": "Synthwave", "primary": "#ff2d95", "secondary": "#22d3ee",
		"requirement": "starter", "count": 0},
	{"id": "electric-blue", "name": "Electric Blue", "primary": "#168bff", "secondary": "#22d3ee",
		"requirement": "starter", "count": 0},
	{"id": "arctic-white", "name": "Arctic White", "primary": "#e8f0ff", "secondary": "#8b5cf6",
		"requirement": "starter", "count": 0},
	{"id": "solar-flare", "name": "Solar Flare", "primary": "#ff8a00", "secondary": "#ffe45e",
		"requirement": "races", "count": 1},
	{"id": "ion-storm", "name": "Ion Storm", "primary": "#8b5cf6", "secondary": "#34d399",
		"requirement": "best", "count": 5000},
]
const ROUTES: Array[Dictionary] = [
	{"id": "neon-loop", "name": "Neon Loop", "subtitle": "Downtown night circuit",
		"requirement": "starter", "count": 0},
	{"id": "skyline-run", "name": "Skyline Run", "subtitle": "Elevated expressway",
		"requirement": "races", "count": 2},
	{"id": "void-causeway", "name": "Void Causeway", "subtitle": "Expert high-speed route",
		"requirement": "gold", "count": 1},
]


static func item(items: Array[Dictionary], id: String) -> Dictionary:
	for entry: Dictionary in items:
		if entry.id == id:
			return entry
	assert(false, "Unknown catalog ID: " + id)
	return {}


static func unlocked(entry: Dictionary, profile: Dictionary) -> bool:
	return entry.requirement == "starter" or int(profile[entry.requirement]) >= int(entry.count)


static func requirement(entry: Dictionary) -> String:
	match entry.requirement:
		"races": return "Finish %d races" % int(entry.count)
		"gold": return "Earn %d gold finishes" % int(entry.count)
		"best": return "Score %d in one race" % int(entry.count)
	return "Available from the start"


static func configuration(kind: String = "standard") -> Dictionary:
	var config: Dictionary = {
		"acceleration": 42.0, "braking": 64.0, "drag": 10.0, "maximum_speed": 120.0,
		"steering_rate": 1.8, "stage_length": 5000.0, "duration": 90.0,
		"capacity": 6.0, "initial_charge": 4.0, "consumption": 1.0, "recharge": 0.3,
		"boost_acceleration": 21.0, "boost_multiplier": 1.2, "boost_points": 25.0,
		"bronze": 5700.0, "silver": 5880.0, "gold": 6050.0, "density": 0.2,
		"centrifugal": 0.00012, "rest_ratio": 0.22, "offroad_limit": 0.55,
		"offroad_drag": 55.0, "offroad_grip": 0.58, "wall_loss": 70.0, "grade_scale": 38.0,
		"crash_steering": 0.35, "drift_steering": 1.28, "drift_loss": 9.0,
		"drift_min": 0.58, "drift_curve_speed": 0.8, "drift_hard": 0.72,
		"drift_exit": 0.34, "drift_brake": 0.18, "drift_curve": 0.18,
	}
	if kind == "novice":
		config.merge({
			"acceleration": 44.0, "braking": 62.0, "drag": 9.0, "maximum_speed": 112.0,
			"steering_rate": 1.65, "stage_length": 4500.0, "duration": 100.0,
			"capacity": 7.0, "initial_charge": 7.0, "recharge": 0.45,
			"boost_acceleration": 18.0, "boost_multiplier": 1.18, "boost_points": 18.0,
			"bronze": 5200.0, "silver": 5400.0, "gold": 5550.0, "density": 0.14,
			"centrifugal": 0.000105, "rest_ratio": 0.28, "offroad_limit": 0.6,
			"offroad_drag": 48.0, "offroad_grip": 0.65, "wall_loss": 58.0, "grade_scale": 32.0,
			"crash_steering": 0.45, "drift_steering": 1.22, "drift_loss": 7.0,
			"drift_min": 0.55, "drift_curve_speed": 0.78, "drift_hard": 0.68,
			"drift_exit": 0.3, "drift_brake": 0.16, "drift_curve": 0.16,
		}, true)
	elif kind == "expert":
		config.merge({
			"acceleration": 40.0, "braking": 68.0, "drag": 11.0, "maximum_speed": 128.0,
			"steering_rate": 2.0, "stage_length": 5500.0, "duration": 84.0,
			"capacity": 5.0, "initial_charge": 3.0, "consumption": 1.15, "recharge": 0.2,
			"boost_acceleration": 24.0, "boost_multiplier": 1.22, "boost_points": 35.0,
			"bronze": 6200.0, "silver": 6375.0, "gold": 6525.0, "density": 0.28,
			"centrifugal": 0.00013, "rest_ratio": 0.2, "offroad_limit": 0.52,
			"offroad_drag": 62.0, "offroad_grip": 0.55, "wall_loss": 78.0, "grade_scale": 42.0,
			"crash_steering": 0.32, "drift_steering": 1.32, "drift_loss": 10.0,
			"drift_min": 0.6, "drift_curve_speed": 0.82, "drift_hard": 0.74,
			"drift_exit": 0.36, "drift_brake": 0.2, "drift_curve": 0.2,
		}, true)
	return config

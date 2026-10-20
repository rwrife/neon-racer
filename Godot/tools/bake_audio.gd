extends SceneTree

const RATE: int = 22050
const BEAT: float = 60.0 / 108.0
const ROOTS: Array[float] = [55.0, 55.0, 65.41, 73.42, 49.0, 49.0, 65.41, 73.42]
const CUES: Dictionary = {
	"confirm": [0.12, 520, 780, 0], "pass": [0.14, 720, 980, 0.02],
	"near_miss": [0.18, 900, 1500, 0.04], "combo": [0.24, 660, 1100, 0],
	"checkpoint": [0.38, 440, 880, 0], "boost": [0.32, 180, 720, 0.12],
	"crash": [0.42, 100, 45, 0.34], "finish": [0.7, 440, 1320, 0],
	"failure": [0.65, 330, 110, 0.04],
}
var random: RandomNumberGenerator = RandomNumberGenerator.new()
var low: float = 0.0
var shimmer: float = 0.0
var failed: bool = false


func _initialize() -> void:
	var result: Error = DirAccess.make_dir_recursive_absolute("res://assets/audio")
	if result != OK:
		push_error("Cannot create audio output: " + error_string(result))
		quit(1)
		return
	for stem: String in ["bass", "arpeggio", "pad", "drums", "pulse"]:
		bake(stem, BEAT * 16, music_sample.bind(stem), true)
	for engine: String in ["fundamental", "harmonics", "whine"]:
		bake(engine, 1.0, engine_sample.bind(engine), true)
	for environment: String in ["city", "coast", "desert", "tunnel"]:
		random.seed = 1234
		low = 0.0
		shimmer = 0.0
		bake(environment, 4.0, ambience_sample.bind(environment), true)
	random.seed = 0xA11CE
	bake("tires", 2.0, func(_time: float) -> float: return random.randf_range(-1, 1) * 0.22, true)
	for cue: String in CUES:
		random.seed = 0x51F
		bake(cue, float(CUES[cue][0]), cue_sample.bind(cue), false)
	print("Baked original procedural music, vehicle layers, ambience, and cues.")
	quit(1 if failed else 0)


func bake(name: String, duration: float, sample: Callable, loop: bool) -> void:
	var count: int = int(RATE * duration)
	var data: PackedByteArray = []
	data.resize(count * 2)
	for frame: int in range(count):
		var value: float = float(sample.call(float(frame) / RATE))
		data.encode_u16(frame * 2, clampi(roundi(value * 32767), -32768, 32767) & 0xffff)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	stream.loop_end = count
	var result: Error = ResourceSaver.save(stream, "res://assets/audio/" + name + ".res", ResourceSaver.FLAG_COMPRESS)
	if result != OK:
		failed = true
		push_error("Audio bake failed for " + name + ": " + error_string(result))


func gate(time: float, interval: float, decay: float) -> float:
	return exp(-fmod(time, interval) / interval * decay)


func noise(time: float, frequency: float) -> float:
	var value: float = sin(time * frequency * 12.9898) * 43758.5453
	return (value - floor(value)) * 2 - 1


func music_sample(time: float, stem: String) -> float:
	var root: float = ROOTS[int(time / (BEAT * 2)) % ROOTS.size()]
	match stem:
		"bass":
			return tanh((sin(time * root * TAU) + 0.38 * sin(time * root * TAU * 2)
				+ 0.12 * sin(time * root * TAU * 3)) * gate(time, BEAT / 2, 7)) * 0.38
		"arpeggio":
			var ratios: Array[float] = [2, 3, 4, 6, 4, 3, 2, 1.5]
			var frequency: float = root * ratios[int(time / (BEAT / 2)) % ratios.size()]
			return (sin(time * frequency * TAU) + 0.18 * sin(time * frequency * TAU * 2)) \
				* gate(time, BEAT / 2, 5.5) * 0.2
		"pad":
			var chord: Array[float] = [1, 1.5, 2, 2.5]
			var swell: float = 0.62 + 0.38 * sin(time / (BEAT * 8) * TAU)
			var pad: float = 0
			for i: int in range(chord.size()):
				pad += sin(time * root * chord[i] * TAU + i * 0.7) * 0.08
			return tanh(pad * swell) * 0.9
		"drums":
			var position: float = fmod(time, BEAT * 4)
			var kick_phase: float = fmod(position, BEAT * 2)
			var kick: float = (sin(time * (54 + 80 * exp(-kick_phase * 24)) * TAU)
				* exp(-kick_phase * 18) * 0.9) if kick_phase < 0.18 else 0.0
			var offset: float = absf(position - BEAT * 2)
			var snare: float = noise(time, 7900) * exp(-offset * 18) * 0.28 if offset < 0.16 else 0.0
			var hat: float = noise(time, 12400) * exp(-fmod(position, BEAT / 2) * 40) * 0.12
			return tanh(kick + snare + hat) * 0.32
		"pulse":
			return sin(time * 880 * TAU) * gate(time, BEAT, 9) * 0.22
	assert(false, "Unknown music stem " + stem)
	return 0.0


func engine_sample(time: float, layer: String) -> float:
	match layer:
		"fundamental":
			var phase: float = time * 55 * TAU
			return tanh(sin(phase) * 0.52 + sin(phase * 2) * 0.22 + sin(phase * 3) * 0.1) * 0.42
		"harmonics":
			var phase: float = time * 91 * TAU
			return tanh(sin(phase) * 0.34 + sin(phase * 1.49) * 0.22 + sin(phase * 2.01) * 0.14
				+ sin(time * 8 * TAU) * 0.04) * 0.34
		"whine":
			var sweep: float = 360 + sin(time * 0.5 * TAU) * 42
			return tanh(sin(time * sweep * TAU) * 0.24 + sin(time * sweep * TAU * 2) * 0.1
				+ sin(time * 1420 * TAU) * 0.08) * 0.26
	assert(false, "Unknown engine layer " + layer)
	return 0.0


func ambience_sample(time: float, environment: String) -> float:
	var white: float = random.randf_range(-1, 1)
	low = low * 0.985 + white * 0.015
	shimmer = shimmer * 0.74 + white * 0.26
	match environment:
		"city": return low * 0.24 + sin(time * 62 * TAU) * 0.08 + sin(time * 123 * TAU) * 0.035
		"coast": return low * 0.34 + shimmer * 0.035 + sin(time * 0.21 * TAU) * 0.08
		"desert": return low * 0.18 + shimmer * (0.08 + 0.05 * sin(time * 0.13 * TAU))
		"tunnel": return low * 0.42 + sin(time * 92 * TAU) * 0.07 + sin(time * 184 * TAU) * 0.035
	assert(false, "Unknown ambience " + environment)
	return 0.0


func cue_sample(time: float, cue: String) -> float:
	var spec: Array = CUES[cue]
	var progress: float = time / float(spec[0])
	var frequency: float = lerpf(float(spec[1]), float(spec[2]), progress)
	var envelope: float = sin(PI * minf(progress / 0.08, 1)) * pow(maxf(0, 1 - progress), 1.8)
	return (sin(time * frequency * TAU) * 0.55 + random.randf_range(-1, 1) * float(spec[3])) * envelope

class_name RacerCar
extends Node3D

const WIDTH: float = 2.02
const LENGTH: float = 4.45
const HEIGHT: float = LENGTH * 0.88

var animated: Node3D = Node3D.new()
var body_root: Node3D = Node3D.new()
var trim_materials: Array[StandardMaterial3D] = []
var tail_material: StandardMaterial3D
var flame_material: ShaderMaterial = ShaderMaterial.new()
var flames: Array[MeshInstance3D] = []
var trails: Array[GPUParticles3D] = []
var pool_material: ShaderMaterial = ShaderMaterial.new()
var glow: OmniLight3D = OmniLight3D.new()


func _init(color: Color = Color("#ff2d95"), accent: Color = Color("#22d3ee"), use_trails: bool = false) -> void:
	add_child(animated)
	animated.add_child(body_root)
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "RoadsterBody"
	body.mesh = preload("res://assets/roadster-colored.res")
	var bounds: AABB = body.mesh.get_aabb()
	body.scale = Vector3(WIDTH / bounds.size.x, HEIGHT, LENGTH / bounds.size.z)
	body.position = Vector3(
		-(bounds.position.x + bounds.size.x / 2) * body.scale.x,
		-bounds.position.y * body.scale.y,
		-(bounds.position.z + bounds.size.z / 2) * body.scale.z)
	var paint: ShaderMaterial = ShaderMaterial.new()
	paint.shader = preload("res://shaders/paint.gdshader")
	paint.set_shader_parameter("paint", color)
	body.material_override = paint
	body_root.add_child(body)
	set_meta("center_height", bounds.size.y * body.scale.y * 0.5)
	var trim: StandardMaterial3D = RacerWorld.neon(accent)
	var warm: StandardMaterial3D = RacerWorld.neon(color)
	trim_materials.assign([trim, warm])
	tail_material = RacerWorld.neon(Color("#ff123c"))
	for side: float in [-1.0, 1.0]:
		add_neon_path("SideSkirt", [
			Vector3(side * WIDTH * 0.46, HEIGHT * 0.055, -LENGTH * 0.36),
			Vector3(side * WIDTH * 0.49, HEIGHT * 0.055, LENGTH * 0.34)], 0.018, trim)
		add_neon_path("Shoulder", [
			Vector3(side * WIDTH * 0.42, HEIGHT * 0.17, -LENGTH * 0.40),
			Vector3(side * WIDTH * 0.48, HEIGHT * 0.18, -LENGTH * 0.16),
			Vector3(side * WIDTH * 0.48, HEIGHT * 0.18, LENGTH * 0.36)], 0.012, warm)
		add_neon_path("Canopy", [
			Vector3(side * WIDTH * 0.36, HEIGHT * 0.20, -LENGTH * 0.20),
			Vector3(side * WIDTH * 0.29, HEIGHT * 0.30, -LENGTH * 0.04),
			Vector3(side * WIDTH * 0.30, HEIGHT * 0.29, LENGTH * 0.15),
			Vector3(side * WIDTH * 0.38, HEIGHT * 0.20, LENGTH * 0.30)], 0.012, trim)
		for axle: float in [-0.31, 0.31]:
			var ring: MeshInstance3D = MeshInstance3D.new()
			ring.name = "WheelHalo"
			var torus: TorusMesh = TorusMesh.new()
			torus.inner_radius = LENGTH * 0.061 - 0.017
			torus.outer_radius = LENGTH * 0.061 + 0.017
			torus.rings = 24
			torus.ring_segments = 8
			ring.mesh = torus
			ring.material_override = trim
			ring.position = Vector3(side * WIDTH * 0.49, HEIGHT * 0.077, LENGTH * axle)
			ring.rotation.z = PI / 2
			body_root.add_child(ring)
		add_box("Headlight", Vector3(WIDTH * 0.27, 0.035, 0.04),
			Vector3(side * WIDTH * 0.29, HEIGHT * 0.13, -LENGTH * 0.49), trim)
	add_box("BrakeLight", Vector3(WIDTH * 0.82, 0.045, 0.045),
		Vector3(0, HEIGHT * 0.14, LENGTH * 0.50), tail_material)
	add_box("FrontSplitter", Vector3(WIDTH * 0.82, 0.028, 0.04),
		Vector3(0, HEIGHT * 0.055, -LENGTH * 0.50), warm)
	for index: int in range(5):
		add_box("RearDiffuser", Vector3(0.025, 0.09, LENGTH * 0.08),
			Vector3((index - 2) * WIDTH * 0.14, HEIGHT * 0.045, LENGTH * 0.44), trim)
	var dark: StandardMaterial3D = RacerWorld.paint(Color("#100c22"))
	add_box("Spoiler", Vector3(WIDTH * 0.98, 0.09, 0.20), Vector3(0, 1.04, LENGTH / 2 - 0.24), dark)
	for side: float in [-1.0, 1.0]:
		add_box("SpoilerUpright", Vector3(0.08, 0.32, 0.08),
			Vector3(side * WIDTH * 0.32, 0.84, LENGTH / 2 - 0.25), dark)
	build_exhaust(accent, use_trails)
	build_underglow(accent)
	update_effects(0, 0, false, false, 0, 0, false, false)


func add_box(part_name: String, dimensions: Vector3, offset: Vector3, material: Material) -> void:
	var part: MeshInstance3D = RacerWorld.box(body_root, dimensions, offset, material)
	part.name = part_name


func add_neon_path(part_name: String, points: Array[Vector3], radius: float, material: Material) -> void:
	for index: int in range(points.size() - 1):
		var delta: Vector3 = points[index + 1] - points[index]
		var cylinder: CylinderMesh = CylinderMesh.new()
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		cylinder.height = delta.length()
		cylinder.radial_segments = 6
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "%s%d" % [part_name, body_root.get_child_count()]
		node.mesh = cylinder
		node.material_override = material
		node.position = (points[index] + points[index + 1]) / 2
		node.quaternion = Quaternion(Vector3.UP, delta.normalized())
		body_root.add_child(node)


func build_exhaust(accent: Color, use_trails: bool) -> void:
	flame_material.shader = preload("res://shaders/exhaust.gdshader")
	flame_material.set_shader_parameter("tint", accent)
	for side: float in [-1.0, 1.0]:
		var flame: MeshInstance3D = MeshInstance3D.new()
		flame.name = "BoostExhaust"
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 0
		cone.bottom_radius = 0.5
		cone.height = 1
		cone.radial_segments = 12
		flame.mesh = cone
		flame.material_override = flame_material
		flame.position = Vector3(side * WIDTH * 0.27, HEIGHT * 0.065, LENGTH / 2 + 0.06)
		flame.rotation.x = PI / 2
		body_root.add_child(flame)
		flames.append(flame)
		if use_trails:
			var particles: GPUParticles3D = GPUParticles3D.new()
			particles.name = "BoostTrail"
			particles.emitting = false
			particles.amount = 48
			particles.lifetime = 0.38
			particles.local_coords = false
			particles.visibility_aabb = AABB(Vector3(-5, -3, -5), Vector3(10, 7, 18))
			particles.position = flame.position
			var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
			process.direction = Vector3.BACK
			process.spread = 8
			process.initial_velocity_min = 4
			process.initial_velocity_max = 10
			process.gravity = Vector3(0, -0.4, 0)
			process.color = accent
			var gradient: Gradient = Gradient.new()
			gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
			var ramp: GradientTexture1D = GradientTexture1D.new()
			ramp.gradient = gradient
			process.color_ramp = ramp
			particles.process_material = process
			var material: StandardMaterial3D = RacerWorld.neon(accent)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			material.vertex_color_use_as_albedo = true
			var fade: GradientTexture2D = GradientTexture2D.new()
			fade.gradient = gradient
			fade.width = 32
			fade.height = 32
			fade.fill = GradientTexture2D.FILL_RADIAL
			fade.fill_from = Vector2(0.5, 0.5)
			fade.fill_to = Vector2(0.5, 0)
			material.albedo_texture = fade
			var quad: QuadMesh = QuadMesh.new()
			quad.size = Vector2(0.08, 0.32)
			quad.material = material
			particles.draw_pass_1 = quad
			body_root.add_child(particles)
			trails.append(particles)


func build_underglow(accent: Color) -> void:
	glow.name = "UnderglowLight"
	glow.position = Vector3(0, 0.16, 0)
	glow.light_color = accent
	glow.omni_range = 4.2
	animated.add_child(glow)
	var pool: MeshInstance3D = MeshInstance3D.new()
	pool.name = "UnderglowPool"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(WIDTH * 1.65, LENGTH * 1.12)
	pool.mesh = plane
	pool_material.shader = preload("res://shaders/underglow.gdshader")
	pool_material.set_shader_parameter("tint", accent)
	pool.material_override = pool_material
	pool.position.y = 0.055
	animated.add_child(pool)


func update_effects(steering: float, speed: float, boosting: bool, braking: bool, slip: float,
		time: float, reduce_motion: bool, reduce_flashes: bool) -> void:
	animated.position.y = 0 if reduce_motion else sin(time * 3.1 + absf(speed) * 0.025) * (0.032 if boosting else 0.018)
	animated.rotation.x = 0 if reduce_motion else (-0.045 if braking else 0.02 if boosting else 0.0)
	animated.rotation.z = 0 if reduce_motion else -steering * 0.085 - slip * 0.025
	body_root.rotation.y = -slip * 0.38
	tail_material.emission_energy_multiplier = 3.0 if braking else 1.25
	var pulse: float = 0.78 + (0.0 if reduce_flashes or reduce_motion else sin(time * 31) * 0.18)
	var width: float = 0.48 + pulse * 0.08 if boosting else 0.22
	var length: float = 0.62 + clampf(absf(speed) / 55, 0, 1.6) * 0.24 if boosting else 0.24
	for flame: MeshInstance3D in flames:
		flame.scale = Vector3(width, length, width)
		flame.position.z = LENGTH / 2 + 0.06 + length * 0.35
	flame_material.set_shader_parameter("strength", 2.9 + pulse if boosting else 0.75)
	flame_material.set_shader_parameter("opacity", 0.72 if boosting else 0.18)
	pool_material.set_shader_parameter("strength", 2.0 + pulse * 0.4 if boosting else 1.1)
	glow.light_energy = 2.8 + pulse * 0.6 if boosting else 1.3
	var trim_pulse: float = 0 if reduce_flashes or reduce_motion else sin(time * 2) * 0.12
	for material: StandardMaterial3D in trim_materials:
		material.emission_energy_multiplier = (2.8 if boosting else 1.65) + trim_pulse
	for particles: GPUParticles3D in trails:
		particles.emitting = boosting and not reduce_motion and not reduce_flashes


func set_effects_paused(paused: bool) -> void:
	for particles: GPUParticles3D in trails:
		particles.speed_scale = 0 if paused else 1

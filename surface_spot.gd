extends PointLight2D

@export var player_reference: CharacterBody2D

var flashlight: HandFlashlight
@export var surfaces_root: Node2D

@export var near_distance: float = 60.0
@export var far_distance: float = 650.0

@export var near_diameter: float = 80.0
@export var far_diameter: float = 300.0

@export var near_energy: float = 1.1
@export var far_energy: float = 0.25

var surfaces: Array[LightSurface] = []


func _ready() -> void:
	enabled = false

	if player_reference == null or surfaces_root == null:
		push_warning(
            "SurfaceSpot: назначь Player Reference и Surfaces Root."
		)
		set_process(false)
		return

	flashlight = player_reference.get_node_or_null(
        "FlashlightPivot"
	) as HandFlashlight

	if flashlight == null:
		push_warning(
            "SurfaceSpot: внутри Player не найден FlashlightPivot "
			+ "со скриптом HandFlashlight."
		)
		set_process(false)
		return

	for child in surfaces_root.get_children():
		if child is LightSurface:
			surfaces.append(child as LightSurface)

	create_spot_texture()

	color = Color(1.0, 0.94, 0.78)

func _process(_delta: float) -> void:
	enabled = false

	if not is_instance_valid(flashlight):
		return

	if not flashlight.is_equipped:
		return

	var mouse_position: Vector2 = get_global_mouse_position()
	var surface: LightSurface = find_surface(mouse_position)

	if surface == null:
		return

	var origin: Vector2 = flashlight.light_origin.global_position
	var distance: float = origin.distance_to(mouse_position)

	# Увеличенная дальность для большой комнаты.
	var distance_ratio: float = clampf(
		distance / 2500.0,
		0.0,
		1.0
	)

	# Вблизи пятно компактное, вдали — широкое.
	var diameter: float = lerpf(
		160.0,
		600.0,
		distance_ratio
	)

	global_position = mouse_position
	global_rotation = deg_to_rad(surface.spot_rotation_degrees)
	scale = surface.spot_shape * (diameter / 256.0)

	# Высокая яркость с умеренным ослаблением вдаль.
	energy = lerpf(
		2.8,
		1.4,
		distance_ratio
	) * surface.brightness_multiplier

	enabled = true


	global_position = mouse_position
	global_rotation = deg_to_rad(surface.spot_rotation_degrees)

	scale = surface.spot_shape * (diameter / 256.0)

	energy = lerpf(
		near_energy,
		far_energy,
		distance_ratio
	) * surface.brightness_multiplier

	# Плавно гасим пятно у предела дальности.
	energy *= 1.0 - smoothstep(0.85, 1.0, distance_ratio)

	enabled = energy > 0.001


func find_surface(world_point: Vector2) -> LightSurface:
	for surface in surfaces:
		if surface.contains_world_point(world_point):
			return surface

	return null


func create_spot_texture() -> void:
	var gradient: Gradient = Gradient.new()

	gradient.offsets = PackedFloat32Array([
		0.0, 0.25, 0.65, 1.0
	])

	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.85, 0.85, 0.85, 1.0),
		Color(0.25, 0.25, 0.25, 1.0),
		Color(0.0, 0.0, 0.0, 1.0)
	])

	var spot_texture: GradientTexture2D = GradientTexture2D.new()

	spot_texture.width = 256
	spot_texture.height = 256
	spot_texture.gradient = gradient
	spot_texture.fill = GradientTexture2D.FILL_RADIAL
	spot_texture.fill_from = Vector2(0.5, 0.5)
	spot_texture.fill_to = Vector2(1.0, 0.5)

	texture = spot_texture

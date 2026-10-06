extends PointLight2D

@export var player_reference: CharacterBody2D
@export var surfaces_root: Node2D

@export var near_distance: float = 60.0
@export var far_distance: float = 2500.0

@export var near_diameter: float = 160.0
@export var far_diameter: float = 600.0

@export var near_energy: float = 2.8
@export var far_energy: float = 1.4

var flashlight: HandFlashlight
var surfaces: Array[LightSurface] = []

const SPOT_RESOLUTION: int = 128

var original_spot: Image
var clipped_spot: Image
var clipped_texture: ImageTexture

var previous_polygon: PackedVector2Array = PackedVector2Array()

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
			"SurfaceSpot: не найден FlashlightPivot "
			+ "со скриптом HandFlashlight."
		)
		set_process(false)
		return

	for child in surfaces_root.get_children():
		if child is LightSurface:
			surfaces.append(child as LightSurface)

	if surfaces.is_empty():
		push_warning(
			"SurfaceSpot: в Surfaces Root нет узлов "
			+ "со скриптом LightSurface."
		)
		set_process(false)
		return

	create_spot_texture()

	color = Color(1.0, 0.94, 0.78)
	shadow_enabled = false
	offset = Vector2.ZERO
	texture_scale = 1.0


func _process(_delta: float) -> void:
	enabled = false

	if not is_instance_valid(flashlight):
		return

	if not flashlight.is_equipped:
		return

	if not is_instance_valid(flashlight.light_origin):
		return

	var mouse_position: Vector2 = get_global_mouse_position()
	var surface: LightSurface = find_surface(mouse_position)

	if surface == null:
		return

	var origin: Vector2 = flashlight.light_origin.global_position
	var distance: float = origin.distance_to(mouse_position)

	var distance_ratio: float = clampf(
		(distance - near_distance)
		/ maxf(far_distance - near_distance, 1.0),
		0.0,
		1.0
	)

	var diameter: float = lerpf(
		near_diameter,
		far_diameter,
		distance_ratio
	)

	global_position = mouse_position
	global_rotation = deg_to_rad(surface.spot_rotation_degrees)
	scale = surface.spot_shape * (
		diameter / float(SPOT_RESOLUTION)
	)

	energy = lerpf(
		near_energy,
		far_energy,
		distance_ratio
	) * surface.brightness_multiplier
	
	update_surface_mask(surface)
	enabled = energy > 0.001


func find_surface(world_point: Vector2) -> LightSurface:
	for surface in surfaces:
		if surface.contains_world_point(world_point):
			return surface

	return null


func create_spot_texture() -> void:
	original_spot = Image.create(
		SPOT_RESOLUTION,
		SPOT_RESOLUTION,
		false,
		Image.FORMAT_RGBA8
	)

	for y in range(SPOT_RESOLUTION):
		for x in range(SPOT_RESOLUTION):
			var uv: Vector2 = Vector2(
				float(x) + 0.5,
				float(y) + 0.5
			) / float(SPOT_RESOLUTION)

			var radius: float = (
				uv - Vector2(0.5, 0.5)
			).length() * 2.0

			var brightness: float = (
				1.0 - smoothstep(0.1, 1.0, radius)
			)

			original_spot.set_pixel(
				x,
				y,
				Color(brightness, brightness, brightness, 1.0)
			)

	clipped_spot = original_spot.duplicate() as Image
	clipped_texture = ImageTexture.create_from_image(clipped_spot)
	texture = clipped_texture


func update_surface_mask(surface: LightSurface) -> void:
	var local_polygon: PackedVector2Array = PackedVector2Array()

	# Переводим границы поверхности в координаты источника света.
	for vertex in surface.polygon:
		var world_vertex: Vector2 = surface.to_global(
			vertex + surface.offset
		)

		local_polygon.append(to_local(world_vertex))

	# Если положение и форма относительно поверхности не изменились,
	# повторно пересчитывать изображение не нужно.
	if local_polygon == previous_polygon:
		return

	previous_polygon = local_polygon

	var half_size: float = float(SPOT_RESOLUTION) * 0.5

	for y in range(SPOT_RESOLUTION):
		for x in range(SPOT_RESOLUTION):
			var point: Vector2 = Vector2(
				float(x) + 0.5 - half_size,
				float(y) + 0.5 - half_size
			)

			var pixel_color: Color = Color.BLACK

			if Geometry2D.is_point_in_polygon(point, local_polygon):
				pixel_color = original_spot.get_pixel(x, y)

			clipped_spot.set_pixel(x, y, pixel_color)

	clipped_texture.update(clipped_spot)
	
func get_light_strength_at(world_point: Vector2) -> float:
	if not enabled or not is_visible_in_tree():
		return 0.0

	if clipped_spot == null:
		return 0.0

	if not is_instance_valid(flashlight):
		return 0.0

	if not flashlight.is_equipped:
		return 0.0

	# Учитываем положение, поворот и масштаб пятна.
	var local_point: Vector2 = to_local(world_point)

	var texture_point: Vector2 = (
		(local_point - offset) / maxf(texture_scale, 0.001)
		+ Vector2(
			float(clipped_spot.get_width()),
			float(clipped_spot.get_height())
		) * 0.5
	)

	var pixel_x: int = floori(texture_point.x)
	var pixel_y: int = floori(texture_point.y)

	if pixel_x < 0 or pixel_y < 0:
		return 0.0

	if pixel_x >= clipped_spot.get_width():
		return 0.0

	if pixel_y >= clipped_spot.get_height():
		return 0.0

	var pixel: Color = clipped_spot.get_pixel(pixel_x, pixel_y)

	return pixel.r * energy
	
	

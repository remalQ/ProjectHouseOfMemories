extends PointLight2D

@export var player_reference: CharacterBody2D
@export var surfaces_root: Node2D

# Сохранено для совместимости с Inspector (в этом алгоритме не используется).
@export_flags_2d_physics var flashlight_blocker_mask: int = 4
@export var desk_shadow_depth_bias: float = 35.0

@export var near_distance: float = 60.0
@export var far_distance: float = 2500.0
@export var near_diameter: float = 160.0
@export var far_diameter: float = 600.0
@export var near_energy: float = 2.8
@export var far_energy: float = 1.4

@export var desk_reference: Area2D
@export var desk_depth_tolerance: float = 0.0
@export var lamp_reference: Area2D
@export var lamp_shadow_depth_bias: float = 0.0

# Тень от силуэта стола на задней стене (упрощённая 2.5D).
@export_range(0.0, 1.0, 0.05) var desk_shadow_strength: float = 1.0
# Сохранено для совместимости с Inspector; новая проекция по глубине его не использует.
@export_range(500.0, 8000.0, 100.0) var desk_shadow_length: float = 4000.0

var desk_surfaces: Array[LightSurface] = []
var flashlight: HandFlashlight
var surfaces: Array[LightSurface] = []

const SPOT_RESOLUTION: int = 128

var original_spot: Image
var clipped_spot: Image
var clipped_texture: ImageTexture

var previous_polygon: PackedVector2Array = PackedVector2Array()
var previous_light_origin: Vector2 = Vector2.ZERO
var previous_desk_transform: Transform2D = Transform2D.IDENTITY
var previous_shadow_active: bool = false
var debug_shadow_pixels: int = 0
var debug_shadow_polygons: int = 0
var has_previous_mask: bool = false


func _ready() -> void:
	enabled = false

	if player_reference == null or surfaces_root == null:
		push_warning("SurfaceSpot: назначь Player Reference и Surfaces Root.")
		set_process(false)
		return

	flashlight = player_reference.get_node_or_null("FlashlightPivot") as HandFlashlight
	if flashlight == null:
		push_warning("SurfaceSpot: не найден FlashlightPivot со скриптом HandFlashlight.")
		set_process(false)
		return

	for child in surfaces_root.get_children():
		if child is LightSurface:
			surfaces.append(child as LightSurface)

	if desk_reference != null:
		for surface_name in ["TopLightSurface", "FrontLightSurface", "InsideLightSurface"]:
			var desk_surface: LightSurface = (
				desk_reference.get_node_or_null(surface_name) as LightSurface
			)
			if desk_surface != null:
				desk_surfaces.append(desk_surface)
	

	if surfaces.is_empty():
		push_warning("SurfaceSpot: в Surfaces Root нет узлов со скриптом LightSurface.")
		set_process(false)
		return

	create_spot_texture()

	color = Color(1.0, 0.94, 0.78)
	shadow_enabled = false
	offset = Vector2.ZERO
	texture_scale = 1.0
	process_priority = 0


func _process(_delta: float) -> void:
	enabled = false
	if is_instance_valid(flashlight):
		flashlight.hide_beam()

	if not is_instance_valid(flashlight):
		return
	if not flashlight.is_equipped:
		return
	if not is_instance_valid(flashlight.light_origin):
		return

	var mouse_position: Vector2 = get_global_mouse_position()
	var origin: Vector2 = flashlight.light_origin.global_position
	var target_position: Vector2 = get_light_target(origin, mouse_position)
	var surface: LightSurface = find_surface(target_position)


	if surface == null:
		return
	# Определяем, какие объекты должен освещать фонарик.
	match surface.name:
		"TopLightSurface", "FrontLightSurface":
			# Поверхности самого стола
			range_z_max = 1

		"InsideLightSurface":
			# Пространство внутри стола
			range_z_max = 1

		"Floor":
			# Пол освещается без засветки мебели
			range_z_max = 0

		_:
			# Остальные поверхности комнаты
			range_z_max = 0

	var distance: float = origin.distance_to(target_position)
	var distance_ratio: float = clampf(
		(distance - near_distance) / maxf(far_distance - near_distance, 1.0),
		0.0,
		1.0
	)

	var diameter: float = lerpf(near_diameter, far_diameter, distance_ratio)

	global_position = target_position
	global_rotation = deg_to_rad(surface.spot_rotation_degrees)
	scale = surface.spot_shape * (diameter / float(SPOT_RESOLUTION))
	energy = lerpf(near_energy, far_energy, distance_ratio) * surface.brightness_multiplier

	# Маска учитывает положение самого фонарика: тень должна двигаться.
	update_surface_mask(surface, origin)
	enabled = energy > 0.001

	if enabled:
		flashlight.update_beam(
			global_position,
			diameter
		)


func find_surface(world_point: Vector2) -> LightSurface:
	for desk_surface in desk_surfaces:
		if desk_surface.contains_world_point(world_point):
			return desk_surface

	for surface in surfaces:
		if surface.contains_world_point(world_point):
			return surface

	return null


func create_spot_texture() -> void:
	original_spot = Image.create(
		SPOT_RESOLUTION, SPOT_RESOLUTION, false, Image.FORMAT_RGBA8
	)

	for y in range(SPOT_RESOLUTION):
		for x in range(SPOT_RESOLUTION):
			var uv: Vector2 = Vector2(
				float(x) + 0.5,
				float(y) + 0.5
			) / float(SPOT_RESOLUTION)

			var radius: float = (uv - Vector2(0.5, 0.5)).length() * 2.0
			var brightness: float = 1.0 - smoothstep(0.1, 1.0, radius)
			original_spot.set_pixel(
				x, y, Color(brightness, brightness, brightness, 1.0)
			)

	clipped_spot = original_spot.duplicate() as Image
	clipped_texture = ImageTexture.create_from_image(clipped_spot)
	texture = clipped_texture


# Нижняя граница задней стены — условная линия, где стена встречает пол.
# Используем координаты самой LightSurface, а не постоянное число.
func get_backwall_floor_y(surface: LightSurface) -> float:
	var lowest_y: float = -INF
	for vertex in surface.polygon:
		var world_vertex: Vector2 = surface.to_global(vertex + surface.offset)
		lowest_y = maxf(lowest_y, world_vertex.y)
	return lowest_y


func should_cast_desk_shadow(surface: LightSurface) -> bool:
	if desk_reference == null or player_reference == null:
		return false
	if surface.name != "Backwall":
		return false
	if desk_reference.get_node_or_null("FlashlightShadowCaster") == null:
		return false

	# Здесь Y корней — условная глубина в комнате (на уровне пола).
	var light_depth: float = player_reference.global_position.y
	var desk_depth: float = desk_reference.global_position.y
	var wall_depth: float = get_backwall_floor_y(surface)

	# Для проекции стол должен лежать между игроком и задней стеной.
	return (
		light_depth > desk_depth + maxf(desk_depth_tolerance, 1.0)
		and desk_depth > wall_depth + 1.0
	)


func should_cast_lamp_shadow(surface: LightSurface) -> bool:
	if lamp_reference == null or player_reference == null:
		return false

	if surface.name != "Backwall":
		return false

	var caster: Node2D = (
		lamp_reference.get_node_or_null("FlashlightShadowCaster") as Node2D
	)
	if caster == null:
		return false

	var depth_point: Marker2D = (
		lamp_reference.get_node_or_null("LightDepthPoint") as Marker2D
	)
	if depth_point == null:
		return false

	var light_depth: float = player_reference.global_position.y
	var lamp_depth: float = depth_point.global_position.y
	var wall_depth: float = get_backwall_floor_y(surface)

	return (
		light_depth > lamp_depth + 1.0
		and lamp_depth > wall_depth + 1.0
	)


func build_lamp_shadow_polygons(
	light_world: Vector2,
	wall_depth: float
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []

	if lamp_reference == null or player_reference == null:
		return result

	var caster: Node2D = (
		lamp_reference.get_node_or_null("FlashlightShadowCaster") as Node2D
	)
	var depth_point: Marker2D = (
		lamp_reference.get_node_or_null("LightDepthPoint") as Marker2D
	)

	if caster == null or depth_point == null:
		return result

	var light_depth: float = player_reference.global_position.y
	var lamp_depth: float = depth_point.global_position.y

	var effective_lamp_depth: float = (
		lamp_depth - lamp_shadow_depth_bias
	)

	var depth_difference: float = light_depth - effective_lamp_depth
	if depth_difference <= 1.0:
		return result

	var projection_factor: float = (
		(light_depth - wall_depth) / depth_difference
	)

	var light_height: float = light_depth - light_world.y

	for child in caster.get_children():
		if not child is Polygon2D:
			continue

		var shape: Polygon2D = child as Polygon2D
		if shape.polygon.size() < 3:
			continue

		var projected_polygon: PackedVector2Array = PackedVector2Array()

		for vertex in shape.polygon:
			var obstacle_world: Vector2 = shape.to_global(
				vertex + shape.offset
			)

			var obstacle_height: float = (
				effective_lamp_depth - obstacle_world.y
			)

			var projected_x: float = (
				light_world.x
				+ (obstacle_world.x - light_world.x) * projection_factor
			)

			var projected_height: float = (
				light_height
				+ (obstacle_height - light_height) * projection_factor
			)

			var projected_y: float = wall_depth - projected_height

			projected_polygon.append(
				to_local(Vector2(projected_x, projected_y))
			)

		result.append(projected_polygon)

	return result


# Приближённая 2.5D-проекция: экранные X/Y точек стола
# переводим в координаты (X, глубина, высота), направляем луч
# от линзы через силуэт стола и пересекаем плоскость задней стены.
# Условная высота точки = глубина её основания - экранный Y.

func build_desk_shadow_polygons(
	light_world: Vector2,
	wall_depth: float
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []

	if desk_reference == null or player_reference == null:
		return result

	var caster: Node2D = (
		desk_reference.get_node_or_null("FlashlightShadowCaster") as Node2D
	)
	if caster == null:
		return result

	var light_depth: float = player_reference.global_position.y
	var desk_depth: float = desk_reference.global_position.y

	# Смещаем условную глубину всей геометрии стола.
	var effective_desk_depth: float = desk_depth - desk_shadow_depth_bias

	var depth_difference: float = light_depth - effective_desk_depth
	if depth_difference <= 1.0:
		return result

	var projection_factor: float = (
		(light_depth - wall_depth)
		/ depth_difference
	)

	var light_height: float = light_depth - light_world.y

	for child in caster.get_children():
		if not child is Polygon2D:
			continue

		var shape: Polygon2D = child as Polygon2D
		if shape.polygon.size() < 3:
			continue

		var projected_polygon: PackedVector2Array = PackedVector2Array()

		for vertex in shape.polygon:
			var obstacle_world: Vector2 = shape.to_global(vertex + shape.offset)

			# Высота рассчитывается относительно той же
			# эффективной глубины, что и проекция.
			var obstacle_height: float = (
				effective_desk_depth - obstacle_world.y
			)

			var projected_x: float = (
				light_world.x
				+ (obstacle_world.x - light_world.x) * projection_factor
			)

			var projected_height: float = (
				light_height
				+ (obstacle_height - light_height) * projection_factor
			)

			var projected_y: float = wall_depth - projected_height

			projected_polygon.append(
				to_local(Vector2(projected_x, projected_y))
			)

		result.append(projected_polygon)

	return result



func update_surface_mask(surface: LightSurface, light_world: Vector2) -> void:
	var local_polygon: PackedVector2Array = PackedVector2Array()
	for vertex in surface.polygon:
		var world_vertex: Vector2 = surface.to_global(vertex + surface.offset)
		local_polygon.append(to_local(world_vertex))

	var cast_desk_shadow: bool = should_cast_desk_shadow(surface)
	var cast_lamp_shadow: bool = should_cast_lamp_shadow(surface)

	var cast_shadow: bool = cast_desk_shadow or cast_lamp_shadow
	var current_desk_transform: Transform2D = Transform2D.IDENTITY
	if desk_reference != null:
		current_desk_transform = desk_reference.global_transform

	if has_previous_mask:
		var same_surface: bool = local_polygon == previous_polygon
		var same_shadow_mode: bool = cast_shadow == previous_shadow_active
		var same_source: bool = (
			light_world.distance_squared_to(previous_light_origin) < 0.25
		)
		var same_desk: bool = current_desk_transform == previous_desk_transform

		if same_surface and same_shadow_mode:
			if not cast_shadow or (same_source and same_desk):
				return

	previous_polygon = local_polygon
	previous_light_origin = light_world
	previous_desk_transform = current_desk_transform
	previous_shadow_active = cast_shadow
	has_previous_mask = true

	var shadow_polygons: Array[PackedVector2Array] = []

	if cast_desk_shadow:
		shadow_polygons.append_array(
			build_desk_shadow_polygons(
				light_world,
				get_backwall_floor_y(surface)
			)
		)

	if cast_lamp_shadow:
		shadow_polygons.append_array(
			build_lamp_shadow_polygons(
				light_world,
				get_backwall_floor_y(surface)
			)
		)
	debug_shadow_pixels = 0
	debug_shadow_polygons = shadow_polygons.size()

	var half_size: float = float(SPOT_RESOLUTION) * 0.5

	for y in range(SPOT_RESOLUTION):
		for x in range(SPOT_RESOLUTION):
			var point: Vector2 = Vector2(
				float(x) + 0.5 - half_size,
				float(y) + 0.5 - half_size
			)

			var pixel_color: Color = Color.TRANSPARENT

			if Geometry2D.is_point_in_polygon(point, local_polygon):
				pixel_color = original_spot.get_pixel(x, y)

				# Вырезаем тень по проекции геометрии стола.
				if cast_shadow:
					for shadow_polygon in shadow_polygons:
						if Geometry2D.is_point_in_polygon(point, shadow_polygon):
							var shadow_factor: float = 1.0 - clampf(
								desk_shadow_strength,
								0.0,
								1.0
							)

							pixel_color = Color(
								pixel_color.r * shadow_factor,
								pixel_color.g * shadow_factor,
								pixel_color.b * shadow_factor,
								pixel_color.a * shadow_factor
							)

							break

			clipped_spot.set_pixel(x, y, pixel_color)

	# Создаём новую текстуру после изменения маски.
	clipped_texture = ImageTexture.create_from_image(clipped_spot)

	# Принудительно назначаем её PointLight2D.
	texture = clipped_texture
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


# Оставляем принятую ранее 2.5D-логику выбора точки попадания.
func get_light_target(from_world: Vector2, to_world: Vector2) -> Vector2:
	if desk_reference == null or player_reference == null:
		return to_world

	var player_depth: float = player_reference.global_position.y
	var desk_depth: float = desk_reference.global_position.y

	if player_depth > desk_depth + desk_depth_tolerance:
		return to_world

	for desk_surface in desk_surfaces:
		if desk_surface.contains_world_point(to_world):
			return to_world

	var ray_direction: Vector2 = to_world - from_world
	if ray_direction.length_squared() < 1.0:
		return to_world

	var direction: Vector2 = ray_direction.normalized()
	var nearest_position: Vector2 = to_world
	var nearest_distance_sq: float = from_world.distance_squared_to(to_world)

	for desk_surface in desk_surfaces:
		var points: PackedVector2Array = desk_surface.polygon
		if points.size() < 3:
			continue

		for i in range(points.size()):
			var next_index: int = (i + 1) % points.size()
			var edge_start: Vector2 = desk_surface.to_global(
				points[i] + desk_surface.offset
			)
			var edge_end: Vector2 = desk_surface.to_global(
				points[next_index] + desk_surface.offset
			)

			var intersection = Geometry2D.segment_intersects_segment(
				from_world, to_world, edge_start, edge_end
			)
			if intersection == null:
				continue

			var hit_position: Vector2 = intersection
			var candidate: Vector2 = hit_position + direction * 2.0
			if not desk_surface.contains_world_point(candidate):
				continue

			var distance_sq: float = from_world.distance_squared_to(candidate)
			if distance_sq < nearest_distance_sq:
				nearest_distance_sq = distance_sq
				nearest_position = candidate

	return nearest_position

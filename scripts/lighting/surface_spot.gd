extends PointLight2D

@export var player_reference: CharacterBody2D
@export var surfaces_root: Node2D

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

# Освещение задней стены, пока основной свет попадает на стол.
@export_range(0.0, 2.0, 0.05) var wall_shadow_energy_multiplier: float = 1.0
@export_range(0.5, 3.0, 0.05) var wall_shadow_size_multiplier: float = 1.6

# Дополнительная подсветка для пары Backwall <-> Floor.
@export_range(0.0, 2.0, 0.05) var wall_from_floor_energy_multiplier: float = 0.75
@export_range(0.5, 3.0, 0.05) var wall_from_floor_size_multiplier: float = 1.0
@export_range(0.0, 2.0, 0.05) var floor_from_wall_energy_multiplier: float = 0.60
@export_range(0.5, 3.0, 0.05) var floor_from_wall_size_multiplier: float = 1.0

# Свет на непрозрачных частях стола, когда луч направлен на заднюю стену.
@export_range(0.0, 2.0, 0.05) var desk_from_wall_energy_multiplier: float = 1.0
@export_range(0.5, 3.0, 0.05) var desk_from_wall_size_multiplier: float = 1.0

# Дополнительная подсветка стола при наведении луча на пол рядом с ним.
@export_range(0.0, 2.0, 0.05) var desk_from_floor_energy_multiplier: float = 0.9
@export_range(0.5, 3.0, 0.05) var desk_from_floor_size_multiplier: float = 1.15

# Переход освещения со стола на пол: без сдвига пятна и без напольной тени.
@export_range(0.0, 2.0, 0.05) var floor_from_desk_energy_multiplier: float = 1.0

# Тень от силуэта стола на задней стене (упрощённая 2.5D).
@export_range(0.0, 1.0, 0.05) var desk_shadow_strength: float = 1.0

var desk_surfaces: Array[LightSurface] = []
var flashlight: HandFlashlight
var surfaces: Array[LightSurface] = []

const SPOT_RESOLUTION: int = 128

var original_spot: Image
var clipped_spot: Image

# Отдельная световая маска для стены. Основной SurfaceSpot остаётся
# источником света на выбранной поверхности (стол, пол, стена и т.д.).
var backwall_surface: LightSurface
var floor_surface: LightSurface
var wall_shadow_light: PointLight2D
var wall_shadow_spot: Image
var floor_spill_light: PointLight2D
var floor_spill_spot: Image
var desk_spill_light: PointLight2D
var desk_spill_spot: Image

var previous_polygon: PackedVector2Array = PackedVector2Array()
var previous_light_origin: Vector2 = Vector2.ZERO
var previous_desk_transform: Transform2D = Transform2D.IDENTITY
var has_previous_mask: bool = false
var previous_lamp_transform: Transform2D = Transform2D.IDENTITY
var previous_shadow_state: int = -1

var previous_wall_polygon: PackedVector2Array = PackedVector2Array()
var previous_wall_light_origin: Vector2 = Vector2.ZERO
var previous_wall_desk_transform: Transform2D = Transform2D.IDENTITY
var previous_wall_lamp_transform: Transform2D = Transform2D.IDENTITY
var previous_wall_shadow_state: int = -1
var has_previous_wall_mask: bool = false


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
			var found_surface: LightSurface = child as LightSurface
			surfaces.append(found_surface)
			if found_surface.name == "Backwall":
				backwall_surface = found_surface
			elif found_surface.name == "Floor":
				floor_surface = found_surface

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

	create_wall_shadow_light()
	create_floor_spill_light()
	create_desk_spill_light()


func _process(_delta: float) -> void:
	enabled = false
	if is_instance_valid(wall_shadow_light):
		wall_shadow_light.enabled = false
	if is_instance_valid(floor_spill_light):
		floor_spill_light.enabled = false
	if is_instance_valid(desk_spill_light):
		desk_spill_light.enabled = false
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

	# Если свет освещает твёрдую часть стола, одновременно подсвечиваем
	# дальнюю стену отдельным источником с перспективной теневой маской.
	if surface.name == "TopLightSurface" or surface.name == "FrontLightSurface":
		update_wall_shadow_light(origin, target_position, diameter)
		update_floor_from_desk_light()
	elif surface.name == "Floor":
		update_wall_from_floor_light(origin)
		update_desk_from_floor_light()
	elif surface.name == "Backwall":
		update_floor_from_wall_light()
		update_desk_from_wall_light(origin, target_position, diameter)


func find_surface(world_point: Vector2) -> LightSurface:
	for desk_surface in desk_surfaces:
		if desk_surface.contains_world_point(world_point):
			return desk_surface

	for surface in surfaces:
		if surface.contains_world_point(world_point):
			return surface

	return null


# Дополнительный PointLight2D освещает Backwall за столом и рядом с полом.
# В нём используется отдельная Image, поэтому основной SurfaceSpot не теряет
# подсветку столешницы, а скрытые надписи по-прежнему ссылаются на SurfaceSpot.
func create_wall_shadow_light() -> void:
	if backwall_surface == null:
		push_warning("SurfaceSpot: Backwall не найдена — вторая световая маска отключена.")
		return

	wall_shadow_light = PointLight2D.new()
	wall_shadow_light.name = "WallShadowSpot"
	add_child(wall_shadow_light)

	# Scale и position основного света постоянно меняются: дочерний
	# источник должен оставаться независимым от этих преобразований.
	wall_shadow_light.set_as_top_level(true)
	wall_shadow_light.enabled = false
	wall_shadow_light.color = color
	wall_shadow_light.shadow_enabled = false
	wall_shadow_light.offset = Vector2.ZERO
	wall_shadow_light.texture_scale = 1.0
	wall_shadow_light.range_z_max = 0
	wall_shadow_light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	wall_shadow_spot = original_spot.duplicate() as Image
	wall_shadow_light.texture = ImageTexture.create_from_image(wall_shadow_spot)


func create_floor_spill_light() -> void:
	if floor_surface == null:
		push_warning("SurfaceSpot: Floor не найдена — дополнительная подсветка пола отключена.")
		return

	floor_spill_light = PointLight2D.new()
	floor_spill_light.name = "FloorSpillSpot"
	add_child(floor_spill_light)

	floor_spill_light.set_as_top_level(true)
	floor_spill_light.enabled = false
	floor_spill_light.color = color
	floor_spill_light.shadow_enabled = false
	floor_spill_light.offset = Vector2.ZERO
	floor_spill_light.texture_scale = 1.0
	floor_spill_light.range_z_max = 0
	floor_spill_light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	floor_spill_spot = original_spot.duplicate() as Image
	floor_spill_light.texture = ImageTexture.create_from_image(floor_spill_spot)


# Отдельный источник для деталей стола на Z=1: он не должен освещать
# Background (-10), Floor или Backwall. Фон под столом остаётся доступным
# для основного света, а непрозрачные детали получают свою маску.
func create_desk_spill_light() -> void:
	if desk_reference == null:
		return

	var has_solid_surface: bool = false
	for desk_surface in desk_surfaces:
		if desk_surface.name == "TopLightSurface" or desk_surface.name == "FrontLightSurface":
			has_solid_surface = true
			break
	if not has_solid_surface:
		push_warning("SurfaceSpot: у Desk нет TopLightSurface / FrontLightSurface.")
		return

	desk_spill_light = PointLight2D.new()
	desk_spill_light.name = "DeskSpillSpot"
	add_child(desk_spill_light)
	desk_spill_light.set_as_top_level(true)
	desk_spill_light.enabled = false
	desk_spill_light.color = color
	desk_spill_light.shadow_enabled = false
	desk_spill_light.offset = Vector2.ZERO
	desk_spill_light.texture_scale = 1.0
	desk_spill_light.range_z_min = 1
	desk_spill_light.range_z_max = 1
	desk_spill_light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	desk_spill_spot = original_spot.duplicate() as Image
	desk_spill_light.texture = ImageTexture.create_from_image(desk_spill_spot)


# Обратная 2.5D-проекция: точка на стене -> условная плоскость стола.
# Используем те же desk_shadow_depth_bias и get_backwall_floor_y(),
# что в build_desk_shadow_polygons(), чтобы свет и тень совпадали.
func update_desk_from_wall_light(
	light_world: Vector2,
	wall_target: Vector2,
	wall_diameter: float
) -> void:
	if desk_spill_light == null or backwall_surface == null:
		return
	if desk_reference == null or player_reference == null:
		return
	if not should_cast_desk_shadow(backwall_surface):
		return

	var light_depth: float = player_reference.global_position.y
	var desk_depth: float = desk_reference.global_position.y - desk_shadow_depth_bias
	var wall_depth: float = get_backwall_floor_y(backwall_surface)
	var depth_span: float = light_depth - wall_depth
	if depth_span <= 1.0:
		return

	var factor: float = (light_depth - desk_depth) / depth_span
	if factor <= 0.0 or factor >= 1.0:
		return

	var light_height: float = light_depth - light_world.y
	var wall_height: float = wall_depth - wall_target.y
	var desk_height: float = lerpf(light_height, wall_height, factor)
	var desk_target: Vector2 = Vector2(
		lerpf(light_world.x, wall_target.x, factor),
		desk_depth - desk_height
	)

	var desk_distance: float = light_world.distance_to(desk_target)
	var distance_ratio: float = clampf(
		(desk_distance - near_distance) / maxf(far_distance - near_distance, 1.0),
		0.0,
		1.0
	)
	var desk_diameter: float = (
		wall_diameter * factor * desk_from_wall_size_multiplier
	)

	desk_spill_light.global_position = desk_target
	desk_spill_light.global_rotation = global_rotation
	desk_spill_light.scale = Vector2.ONE * (desk_diameter / float(SPOT_RESOLUTION))
	desk_spill_light.energy = (
		lerpf(near_energy, far_energy, distance_ratio)
		* desk_from_wall_energy_multiplier
	)
	if desk_spill_light.energy <= 0.001:
		return

	var overlaps_solid: bool = false
	for desk_surface in desk_surfaces:
		if desk_surface.name != "TopLightSurface" and desk_surface.name != "FrontLightSurface":
			continue
		if spot_overlaps_surface(desk_spill_light, desk_surface):
			overlaps_solid = true
			break
	if not overlaps_solid:
		return

	update_desk_spill_mask()
	desk_spill_light.enabled = true


# Когда основное пятно находится на полу, его край может захватывать
# вертикальные части стола. Отдельная маска подсвечивает только
# TopLightSurface и FrontLightSurface (Z=1), не затрагивая InsideLightSurface.
# Используем уже существующий DeskSpillSpot, не создаём новый источник.
func update_desk_from_floor_light() -> void:
	if desk_spill_light == null:
		return

	# Совмещаем пятна в экранном пространстве: на стыке пола и мебели
	# они должны выглядеть непрерывно, без скачка центра луча.
	desk_spill_light.global_transform = global_transform
	desk_spill_light.scale *= desk_from_floor_size_multiplier
	desk_spill_light.energy = energy * desk_from_floor_energy_multiplier

	if desk_spill_light.energy <= 0.001:
		return

	var overlaps_solid: bool = false
	for desk_surface in desk_surfaces:
		if desk_surface.name != "TopLightSurface" and desk_surface.name != "FrontLightSurface":
			continue
		if spot_overlaps_surface(desk_spill_light, desk_surface):
			overlaps_solid = true
			break

	if not overlaps_solid:
		return

	update_desk_spill_mask()
	desk_spill_light.enabled = true


func update_desk_spill_mask() -> void:
	if desk_spill_light == null or desk_spill_spot == null:
		return

	var surface_polygons: Array[PackedVector2Array] = []
	var surface_brightness: Array[float] = []
	for desk_surface in desk_surfaces:
		if desk_surface.name != "TopLightSurface" and desk_surface.name != "FrontLightSurface":
			continue
		var local_polygon: PackedVector2Array = PackedVector2Array()
		for vertex in desk_surface.polygon:
			var world_vertex: Vector2 = desk_surface.to_global(vertex + desk_surface.offset)
			local_polygon.append(desk_spill_light.to_local(world_vertex))
		surface_polygons.append(local_polygon)
		surface_brightness.append(desk_surface.brightness_multiplier)

	var half_size: float = float(SPOT_RESOLUTION) * 0.5
	for y in range(SPOT_RESOLUTION):
		for x in range(SPOT_RESOLUTION):
			var point: Vector2 = Vector2(
				float(x) + 0.5 - half_size,
				float(y) + 0.5 - half_size
			)
			var brightness: float = 0.0
			for i in range(surface_polygons.size()):
				if Geometry2D.is_point_in_polygon(point, surface_polygons[i]):
					brightness = maxf(brightness, surface_brightness[i])
			var pixel_color: Color = Color.TRANSPARENT
			if brightness > 0.0:
				pixel_color = original_spot.get_pixel(x, y) * brightness
			desk_spill_spot.set_pixel(x, y, pixel_color)

	var new_texture: ImageTexture = ImageTexture.create_from_image(desk_spill_spot)
	desk_spill_light.texture = new_texture


# Вспомогательные источники повторяют положение и форму основного пятна.
# Их маски отдельно ограничены полигонами Backwall и Floor. Таким образом
# свет действительно ПЕРЕСЕКАЕТ линию стена/пол, а не проецирует центральную
# точку луча за пределы второй поверхности.
func spot_overlaps_surface(light_node: PointLight2D, surface: LightSurface) -> bool:
	var half_size: float = float(SPOT_RESOLUTION) * 0.5
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF

	for vertex in surface.polygon:
		var world_vertex: Vector2 = surface.to_global(vertex + surface.offset)
		var local_vertex: Vector2 = light_node.to_local(world_vertex)
		min_x = minf(min_x, local_vertex.x)
		max_x = maxf(max_x, local_vertex.x)
		min_y = minf(min_y, local_vertex.y)
		max_y = maxf(max_y, local_vertex.y)

	return (
		min_x < half_size
		and max_x > -half_size
		and min_y < half_size
		and max_y > -half_size
	)


func update_wall_from_floor_light(light_world: Vector2) -> void:
	if wall_shadow_light == null or backwall_surface == null:
		return

	# Совпадение центров позволяет разделить одно световое пятно на две
	# непересекающиеся части, соответствующие геометрии стены и пола.
	wall_shadow_light.global_transform = global_transform
	wall_shadow_light.scale *= wall_from_floor_size_multiplier
	wall_shadow_light.energy = energy * wall_from_floor_energy_multiplier

	if wall_shadow_light.energy <= 0.001:
		return
	if not spot_overlaps_surface(wall_shadow_light, backwall_surface):
		return

	# Для стены используем тот же расчёт перспективных теней, что и раньше.
	update_mask_for_light(
		backwall_surface,
		light_world,
		wall_shadow_light,
		wall_shadow_spot,
		true
	)
	wall_shadow_light.enabled = true


func update_floor_from_wall_light() -> void:
	if floor_spill_light == null or floor_surface == null:
		return

	floor_spill_light.global_transform = global_transform
	floor_spill_light.scale *= floor_from_wall_size_multiplier
	floor_spill_light.energy = energy * floor_from_wall_energy_multiplier

	if floor_spill_light.energy <= 0.001:
		return
	if not spot_overlaps_surface(floor_spill_light, floor_surface):
		return

	update_floor_spill_mask()
	floor_spill_light.enabled = true


# Когда фонарик направлен на стол, освещаем только ту часть того же
# светового пятна, которая фактически пересекается с полом.
# Центр, форма, размер и поворот не изменяются: второго круга нет.
# Напольная тень не рассчитывается — маска содержит только границы Floor.
func update_floor_from_desk_light() -> void:
	if floor_spill_light == null or floor_surface == null:
		return

	floor_spill_light.global_transform = global_transform
	floor_spill_light.energy = energy * floor_from_desk_energy_multiplier

	if floor_spill_light.energy <= 0.001:
		return
	if not spot_overlaps_surface(floor_spill_light, floor_surface):
		return

	update_floor_spill_mask()
	floor_spill_light.enabled = true


func update_floor_spill_mask() -> void:
	if floor_surface == null or floor_spill_spot == null or floor_spill_light == null:
		return

	var local_polygon: PackedVector2Array = PackedVector2Array()
	for vertex in floor_surface.polygon:
		var world_vertex: Vector2 = floor_surface.to_global(vertex + floor_surface.offset)
		local_polygon.append(floor_spill_light.to_local(world_vertex))

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
			floor_spill_spot.set_pixel(x, y, pixel_color)

	# Сохраняем проверенный способ обновления ImageTexture.
	floor_spill_light.texture = ImageTexture.create_from_image(floor_spill_spot)


# Проецируем точку попадания в плоскость стены в той же условной
# системе глубин, что использует build_desk_shadow_polygons().
func update_wall_shadow_light(
	light_world: Vector2,
	target_on_desk: Vector2,
	desk_diameter: float
) -> void:
	if wall_shadow_light == null or backwall_surface == null:
		return
	if desk_reference == null or player_reference == null:
		return
	if not should_cast_desk_shadow(backwall_surface):
		return

	var light_depth: float = player_reference.global_position.y
	var desk_depth: float = desk_reference.global_position.y - desk_shadow_depth_bias
	var wall_depth: float = get_backwall_floor_y(backwall_surface)
	var depth_difference: float = light_depth - desk_depth
	if depth_difference <= 1.0:
		return

	var projection_factor: float = (
		(light_depth - wall_depth) / depth_difference
	)
	var light_height: float = light_depth - light_world.y
	var target_height: float = desk_depth - target_on_desk.y
	var projected_height: float = (
		light_height + (target_height - light_height) * projection_factor
	)

	var wall_target: Vector2 = Vector2(
		light_world.x + (target_on_desk.x - light_world.x) * projection_factor,
		wall_depth - projected_height
	)

	# Не создаём подсветку за пределами плоскости Backwall.
	if not backwall_surface.contains_world_point(wall_target):
		return

	var wall_distance: float = light_world.distance_to(wall_target)
	var wall_distance_ratio: float = clampf(
		(wall_distance - near_distance) / maxf(far_distance - near_distance, 1.0),
		0.0,
		1.0
	)
	var wall_diameter: float = (
		desk_diameter * projection_factor * wall_shadow_size_multiplier
	)

	wall_shadow_light.global_position = wall_target
	wall_shadow_light.global_rotation = deg_to_rad(
		backwall_surface.spot_rotation_degrees
	)
	wall_shadow_light.scale = (
		backwall_surface.spot_shape
		* (wall_diameter / float(SPOT_RESOLUTION))
	)
	wall_shadow_light.energy = (
		lerpf(near_energy, far_energy, wall_distance_ratio)
		* backwall_surface.brightness_multiplier
		* wall_shadow_energy_multiplier
	)

	if wall_shadow_light.energy <= 0.001:
		return

	update_mask_for_light(
		backwall_surface,
		light_world,
		wall_shadow_light,
		wall_shadow_spot,
		true
	)
	wall_shadow_light.enabled = true


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
	texture = ImageTexture.create_from_image(clipped_spot)


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
	wall_depth: float,
	receiver: Node2D = null
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if receiver == null:
		receiver = self

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
				receiver.to_local(Vector2(projected_x, projected_y))
			)

		result.append(projected_polygon)

	return result


# Приближённая 2.5D-проекция: экранные X/Y точек стола
# переводим в координаты (X, глубина, высота), направляем луч
# от линзы через силуэт стола и пересекаем плоскость задней стены.
# Условная высота точки = глубина её основания - экранный Y.

func build_desk_shadow_polygons(
	light_world: Vector2,
	wall_depth: float,
	receiver: Node2D = null
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if receiver == null:
		receiver = self

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
				receiver.to_local(Vector2(projected_x, projected_y))
			)

		result.append(projected_polygon)

	return result


# Публичная обёртка сохранена для совместимости с текущей архитектурой.
func update_surface_mask(surface: LightSurface, light_world: Vector2) -> void:
	update_mask_for_light(surface, light_world, self, clipped_spot, false)


# Генератор маски одинаковый для основного источника и света на стене.
# Расчёты 2.5D теней стола и торшера не меняем.
func update_mask_for_light(
	surface: LightSurface,
	light_world: Vector2,
	receiver: PointLight2D,
	mask_image: Image,
	wall_pass: bool
) -> void:
	var local_polygon: PackedVector2Array = PackedVector2Array()
	for vertex in surface.polygon:
		var world_vertex: Vector2 = surface.to_global(vertex + surface.offset)
		local_polygon.append(receiver.to_local(world_vertex))

	var cast_desk_shadow: bool = should_cast_desk_shadow(surface)
	var cast_lamp_shadow: bool = should_cast_lamp_shadow(surface)
	var cast_shadow: bool = cast_desk_shadow or cast_lamp_shadow
	var shadow_state: int = int(cast_desk_shadow) + int(cast_lamp_shadow) * 2

	var current_desk_transform: Transform2D = Transform2D.IDENTITY
	if desk_reference != null:
		current_desk_transform = desk_reference.global_transform
	var current_lamp_transform: Transform2D = Transform2D.IDENTITY
	if lamp_reference != null:
		current_lamp_transform = lamp_reference.global_transform

	# Независимые кэши нужны, чтобы текстура стены не перезаписывала
	# текстуру стола и чтобы повторно не считать неизменную геометрию.
	if wall_pass:
		if has_previous_wall_mask:
			var same_wall_surface: bool = local_polygon == previous_wall_polygon
			var same_wall_mode: bool = shadow_state == previous_wall_shadow_state
			var same_wall_source: bool = (
				light_world.distance_squared_to(previous_wall_light_origin) < 0.25
			)
			var same_wall_desk: bool = (
				current_desk_transform == previous_wall_desk_transform
			)
			var same_wall_lamp: bool = (
				current_lamp_transform == previous_wall_lamp_transform
			)
			if same_wall_surface and same_wall_mode:
				if not cast_shadow or (
					same_wall_source and same_wall_desk and same_wall_lamp
				):
					return

		previous_wall_polygon = local_polygon
		previous_wall_light_origin = light_world
		previous_wall_desk_transform = current_desk_transform
		previous_wall_lamp_transform = current_lamp_transform
		previous_wall_shadow_state = shadow_state
		has_previous_wall_mask = true
	else:
		if has_previous_mask:
			var same_surface: bool = local_polygon == previous_polygon
			var same_shadow_mode: bool = shadow_state == previous_shadow_state
			var same_source: bool = (
				light_world.distance_squared_to(previous_light_origin) < 0.25
			)
			var same_desk: bool = (
				current_desk_transform == previous_desk_transform
			)
			var same_lamp: bool = (
				current_lamp_transform == previous_lamp_transform
			)
			if same_surface and same_shadow_mode:
				if not cast_shadow or (same_source and same_desk and same_lamp):
					return

		previous_polygon = local_polygon
		previous_light_origin = light_world
		previous_desk_transform = current_desk_transform
		previous_lamp_transform = current_lamp_transform
		previous_shadow_state = shadow_state
		has_previous_mask = true

	var shadow_polygons: Array[PackedVector2Array] = []
	if cast_desk_shadow:
		shadow_polygons.append_array(
			build_desk_shadow_polygons(
				light_world,
				get_backwall_floor_y(surface),
				receiver
			)
		)
	if cast_lamp_shadow:
		shadow_polygons.append_array(
			build_lamp_shadow_polygons(
				light_world,
				get_backwall_floor_y(surface),
				receiver
			)
		)

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
				if cast_shadow:
					for shadow_polygon in shadow_polygons:
						if Geometry2D.is_point_in_polygon(point, shadow_polygon):
							var shadow_factor: float = 1.0 - clampf(
								desk_shadow_strength, 0.0, 1.0
							)
							pixel_color = Color(
								pixel_color.r * shadow_factor,
								pixel_color.g * shadow_factor,
								pixel_color.b * shadow_factor,
								pixel_color.a * shadow_factor
							)
							break
			mask_image.set_pixel(x, y, pixel_color)

	# Текущий проект стабильно показывает маски именно при пересоздании
	# ImageTexture: сохраняем этот способ до отдельной оптимизации.
	var new_texture: ImageTexture = ImageTexture.create_from_image(mask_image)
	receiver.texture = new_texture
	new_texture.update(mask_image)


# Скрытые надписи учитывают основной свет и дополнительные пятна стены/пола.
func get_light_strength_at(world_point: Vector2) -> float:
	if not is_visible_in_tree():
		return 0.0
	if not is_instance_valid(flashlight) or not flashlight.is_equipped:
		return 0.0

	var strength: float = 0.0
	if enabled:
		strength = sample_light_strength(self, clipped_spot, world_point)
	if is_instance_valid(wall_shadow_light) and wall_shadow_light.enabled:
		strength = maxf(
			strength,
			sample_light_strength(wall_shadow_light, wall_shadow_spot, world_point)
		)
	if is_instance_valid(floor_spill_light) and floor_spill_light.enabled:
		strength = maxf(
			strength,
			sample_light_strength(floor_spill_light, floor_spill_spot, world_point)
		)
	return strength


func sample_light_strength(
	light_node: PointLight2D,
	mask_image: Image,
	world_point: Vector2
) -> float:
	if mask_image == null:
		return 0.0
	var local_point: Vector2 = light_node.to_local(world_point)
	var texture_point: Vector2 = (
		(local_point - light_node.offset)
		/ maxf(light_node.texture_scale, 0.001)
		+ Vector2(
			float(mask_image.get_width()),
			float(mask_image.get_height())
		) * 0.5
	)
	var pixel_x: int = floori(texture_point.x)
	var pixel_y: int = floori(texture_point.y)
	if pixel_x < 0 or pixel_y < 0:
		return 0.0
	if pixel_x >= mask_image.get_width():
		return 0.0
	if pixel_y >= mask_image.get_height():
		return 0.0
	return mask_image.get_pixel(pixel_x, pixel_y).r * light_node.energy


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

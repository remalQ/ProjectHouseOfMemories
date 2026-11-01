extends PointLight2D

# SurfaceSpot — главный интерфейс системы освещения (Surface-Driven).
#
# Пайплайн кадра:
#   1. Состояние фонарика (позиция, направление, энергия).
#   2. LightSurfaceResolver: какие поверхности затронуты пятном.
#   3. LightDistributionPlanner: план распределения света
#      (профили поверхностей + связи + 2.5D-проекция).
#   4. LightPassManager: применяет план к световым проходам.
#
# Вне плана пока остаётся только пара Backwall <-> Floor
# (FloorSpillSpot / wall_from_floor) — см. _apply_floor_wall_transitions().


# --- Параметры (имена экспортов сериализованы в сценах) ---

@export var player_reference: CharacterBody2D
@export var surfaces_root: Node2D

@export var desk_reference: Area2D
@export var desk_depth_tolerance: float = 0.0
@export var lamp_reference: Area2D
@export var lamp_shadow_depth_bias: float = 0.0

# Затухание основного пятна по дистанции "фонарик -> точка попадания".
@export var near_distance: float = 60.0
@export var far_distance: float = 2500.0
@export var near_diameter: float = 160.0
@export var far_diameter: float = 600.0
@export var near_energy: float = 2.8
@export var far_energy: float = 1.4

# Условная глубина препятствий для 2.5D-теней.
@export var desk_shadow_depth_bias: float = 35.0

# Пара Backwall <-> Floor (вне плана, см. _apply_floor_wall_transitions).
@export_range(0.0, 2.0, 0.05) var wall_from_floor_energy_multiplier: float = 0.75
@export_range(0.5, 3.0, 0.05) var wall_from_floor_size_multiplier: float = 1.0
@export_range(0.0, 2.0, 0.05) var floor_from_wall_energy_multiplier: float = 0.60
@export_range(0.5, 3.0, 0.05) var floor_from_wall_size_multiplier: float = 1.0

# Сила тени от силуэтов стола и торшера.
@export_range(0.0, 1.0, 0.05) var desk_shadow_strength: float = 1.0

# Связи поверхностей комнаты (Desk<->Wall, Wall<->Floor и т.п.).
@export var surface_connections: Array[LightSurfaceConnection] = []


# --- Состояние ---

var surfaces: Array[LightSurface] = []
var desk_surfaces: Array[LightSurface] = []
var flashlight: HandFlashlight

# Основные поверхности комнаты (находятся по имени узла).
var backwall_surface: LightSurface
var floor_surface: LightSurface

# Модули системы: пересечения, планирование, исполнение, маски.
var surface_resolver: LightSurfaceResolver = LightSurfaceResolver.new()
var distribution_planner: LightDistributionPlanner = \
		LightDistributionPlanner.new()
var light_pass_manager: LightPassManager = LightPassManager.new()
var mask_builder: LightMaskBuilder = LightMaskBuilder.new()

# Вспомогательные источники пары Backwall <-> Floor.
var wall_shadow_light: LightPass
var floor_spill_light: LightPass

# Описания препятствий, отбрасывающих 2.5D-тень: стол и торшер.
var desk_caster: ShadowCasterRef
var lamp_caster: ShadowCasterRef

# Базовая текстура пятна и её копия для маски основного света.
var original_spot: Image
var clipped_spot: Image

const SPOT_RESOLUTION: int = LightMaskBuilder.SPOT_RESOLUTION


# Описание одного препятствия для 2.5D-тени. Глубина берётся из
# depth_point (торшер), а без него — из корня препятствия (стол).
# Эффективная глубина учитывает bias и используется при построении
# полигонов тени.
class ShadowCasterRef:
	var obstacle: Node2D
	var caster: Node2D
	var depth_point: Node2D
	var depth_bias: float = 0.0
	var depth_tolerance: float = 0.0

	func get_depth() -> float:
		if depth_point != null:
			return depth_point.global_position.y
		if obstacle != null:
			return obstacle.global_position.y
		return 0.0

	func get_effective_depth() -> float:
		return get_depth() - depth_bias


# --- Настройка ---

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

	_collect_surfaces()
	_setup_casters()

	if surfaces.is_empty():
		push_warning("SurfaceSpot: в Surfaces Root нет узлов со скриптом LightSurface.")
		set_process(false)
		return

	_setup_pipeline()


# Собирает поверхности комнаты и мебели, находит ключевые по имени.
func _collect_surfaces() -> void:
	for child in surfaces_root.get_children():
		if child is LightSurface:
			var found_surface: LightSurface = child as LightSurface

			surfaces.append(found_surface)

			if found_surface.name == "Backwall":
				backwall_surface = found_surface
			elif found_surface.name == "Floor":
				floor_surface = found_surface

	if desk_reference == null:
		return

	for surface_name in ["TopLightSurface", "FrontLightSurface", "InsideLightSurface"]:
		var desk_surface: LightSurface = (
			desk_reference.get_node_or_null(surface_name) as LightSurface
		)

		if desk_surface != null:
			desk_surfaces.append(desk_surface)


# Описания теневых препятствий: источник глубины и bias — данные.
func _setup_casters() -> void:
	desk_caster = ShadowCasterRef.new()
	if desk_reference != null:
		desk_caster.obstacle = desk_reference
		desk_caster.caster = (
			desk_reference.get_node_or_null("FlashlightShadowCaster") as Node2D
		)
		desk_caster.depth_bias = desk_shadow_depth_bias
		desk_caster.depth_tolerance = desk_depth_tolerance

	lamp_caster = ShadowCasterRef.new()
	if lamp_reference != null:
		lamp_caster.obstacle = lamp_reference
		lamp_caster.caster = (
			lamp_reference.get_node_or_null("FlashlightShadowCaster") as Node2D
		)
		lamp_caster.depth_point = (
			lamp_reference.get_node_or_null("LightDepthPoint") as Node2D
		)
		lamp_caster.depth_bias = lamp_shadow_depth_bias


# Регистрация поверхностей, настройка планировщика и исполнителя.
func _setup_pipeline() -> void:
	create_spot_texture()

	color = Color(1.0, 0.94, 0.78)
	shadow_enabled = false
	offset = Vector2.ZERO
	texture_scale = 1.0
	process_priority = 0

	create_wall_shadow_light()
	create_floor_spill_light()

	surface_resolver.register_surfaces(surfaces, desk_surfaces)
	distribution_planner.set_connections(surface_connections)

	light_pass_manager.initialize(self, original_spot, color, wall_shadow_light)

	# Пару Backwall <-> Floor пока обслуживают FloorSpillSpot и
	# wall_from_floor: исключаем её из плана, чтобы не было
	# двойного света. Остальные пары с полом работают через план.
	var excluded_pairs: Array[PackedStringArray] = []
	if backwall_surface != null and floor_surface != null:
		excluded_pairs.append(PackedStringArray([
			String(backwall_surface.name),
			String(floor_surface.name)
		]))
	light_pass_manager.set_excluded_pairs(excluded_pairs)
	light_pass_manager.set_shadow_handler(
		Callable(self, "update_mask_for_light")
	)


# --- Кадр ---

func _process(_delta: float) -> void:
	_reset_frame_state()

	if not _flashlight_ready():
		return

	var origin: Vector2 = flashlight.light_origin.global_position
	var target_position: Vector2 = get_light_target(
		origin,
		get_global_mouse_position()
	)
	var surface: LightSurface = find_surface(target_position)
	if surface == null:
		return

	# Диапазон Z определяется группой поверхности в профиле: мебель
	# (FURNITURE) освещается на уровне деталей стола, остальная
	# комната — на уровне фона и пола.
	if surface.get_light_group() == LightSurfaceProfile.LightGroup.FURNITURE:
		range_z_max = 1
	else:
		range_z_max = 0

	var distance_ratio: float = _get_distance_ratio(
		origin.distance_to(target_position)
	)
	var diameter: float = lerpf(near_diameter, far_diameter, distance_ratio)

	global_position = target_position
	global_rotation = deg_to_rad(surface.get_spot_rotation_degrees())
	scale = surface.get_spot_shape() * (diameter / float(SPOT_RESOLUTION))

	var base_energy: float = lerpf(near_energy, far_energy, distance_ratio)
	energy = base_energy * surface.get_brightness_multiplier()

	# Пересечения + проекционные кандидаты: поверхности, связанные
	# с основной связью PROJECTED_2_5D. Свет на них проецируется
	# независимо от геометрического пересечения пятна.
	surface_resolver.resolve(self)
	var intersections: Array[LightSurface] = surface_resolver.get_intersections()
	for candidate in _get_projection_candidates(surface):
		if not intersections.has(candidate):
			intersections.append(candidate)

	# План распределения света строится до отрисовки.
	var projection_context: LightDistributionPlanner.ProjectionContext = \
			_build_projection_context(origin, target_position, diameter)
	var plan: LightDistributionPlan = distribution_planner.build_plan(
		self,
		surface,
		intersections,
		projection_context
	)

	# Маска учитывает положение самого фонарика: тень должна двигаться.
	update_surface_mask(surface, origin)
	enabled = energy > 0.001

	if enabled:
		flashlight.update_beam(global_position, diameter)

	_apply_floor_wall_transitions(surface, origin)

	# Исполнитель применяет план к световым проходам.
	light_pass_manager.apply_plan(self, plan, origin, base_energy)


# Сброс состояния проходов в начале кадра.
func _reset_frame_state() -> void:
	surface_resolver.reset()
	light_pass_manager.reset()
	enabled = false
	if is_instance_valid(wall_shadow_light):
		wall_shadow_light.enabled = false
	if is_instance_valid(floor_spill_light):
		floor_spill_light.enabled = false
	if is_instance_valid(flashlight):
		flashlight.hide_beam()


func _flashlight_ready() -> bool:
	if not is_instance_valid(flashlight):
		return false
	if not flashlight.is_equipped:
		return false
	return is_instance_valid(flashlight.light_origin)


func _get_distance_ratio(distance: float) -> float:
	return clampf(
		(distance - near_distance) / maxf(far_distance - near_distance, 1.0),
		0.0,
		1.0
	)


# Контекст кадра для 2.5D-проекций планировщика.
func _build_projection_context(
	origin: Vector2,
	target_position: Vector2,
	diameter: float
) -> LightDistributionPlanner.ProjectionContext:
	var context: LightDistributionPlanner.ProjectionContext = \
			LightDistributionPlanner.ProjectionContext.new()
	context.light_world = origin
	context.light_depth = player_reference.global_position.y
	context.target = target_position
	context.source_diameter = diameter
	context.near_distance = near_distance
	context.far_distance = far_distance
	context.near_energy = near_energy
	context.far_energy = far_energy
	context.resolve_depth = Callable(self, "get_surface_depth")

	if desk_caster != null:
		context.shadow_check = Callable(
			self,
			"should_cast_shadow"
		).bind(desk_caster)

	return context


# Частные переходы пары Backwall <-> Floor (исключённая пара плана).
func _apply_floor_wall_transitions(
	surface: LightSurface,
	origin: Vector2
) -> void:
	if surface == floor_surface:
		update_wall_from_floor_light(origin)
	elif surface == backwall_surface:
		update_floor_from_wall_light()


# --- Проекционные кандидаты ---

# Поверхности, подключённые к заданной проекционными связями
# (PROJECTED_2_5D). Свет на них строится по проекции, а не по
# геометрическому пересечению пятна, поэтому они добавляются
# в кандидаты плана без проверки пересечения.
func _get_projection_candidates(primary: LightSurface) -> Array[LightSurface]:
	var result: Array[LightSurface] = []

	if primary == null:
		return result

	var primary_name: String = String(primary.name)

	for connection in surface_connections:
		if connection == null:
			continue

		if connection.projection_mode \
				!= LightSurfaceProfile.ProjectionMode.PROJECTED_2_5D:
			continue

		var partner_name: String = ""
		if primary_name == connection.surface_a_name:
			partner_name = connection.surface_b_name
		elif connection.bidirectional \
				and primary_name == connection.surface_b_name:
			partner_name = connection.surface_a_name

		if partner_name.is_empty():
			continue

		var partner: LightSurface = _find_surface_by_name(partner_name)
		if partner != null and partner.receives_light() \
				and not result.has(partner):
			result.append(partner)

	return result


func _find_surface_by_name(surface_name: String) -> LightSurface:
	for surface in surfaces:
		if String(surface.name) == surface_name:
			return surface

	for desk_surface in desk_surfaces:
		if String(desk_surface.name) == surface_name:
			return desk_surface

	return null


# --- Пара Backwall <-> Floor (вне плана) ---

# Дополнительный PointLight2D освещает Backwall за столом и рядом с полом.
# В нём используется отдельная Image, поэтому основной SurfaceSpot не теряет
# подсветку столешницы, а скрытые надписи по-прежнему ссылаются на SurfaceSpot.
func create_wall_shadow_light() -> void:
	if backwall_surface == null:
		push_warning("SurfaceSpot: Backwall не найдена — вторая световая маска отключена.")
		return

	wall_shadow_light = LightPass.new()
	add_child(wall_shadow_light)
	wall_shadow_light.setup("WallShadowSpot", color, -1024, 0)
	wall_shadow_light.init_mask(original_spot)


func create_floor_spill_light() -> void:
	if floor_surface == null:
		push_warning("SurfaceSpot: Floor не найдена — дополнительная подсветка пола отключена.")
		return

	floor_spill_light = LightPass.new()
	add_child(floor_spill_light)
	floor_spill_light.setup("FloorSpillSpot", color, -1024, 0)
	floor_spill_light.init_mask(original_spot)


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
	if not LightMaskBuilder.spot_overlaps_surface(wall_shadow_light, backwall_surface):
		return

	# Для стены используем тот же расчёт перспективных теней, что и раньше.
	update_mask_for_light(
		backwall_surface,
		light_world,
		wall_shadow_light,
		wall_shadow_light.mask_image,
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
	if not LightMaskBuilder.spot_overlaps_surface(floor_spill_light, floor_surface):
		return

	update_floor_spill_mask()
	floor_spill_light.enabled = true


func update_floor_spill_mask() -> void:
	if floor_surface == null or floor_spill_light == null:
		return

	var surfaces: Array[LightSurface] = [floor_surface]
	var brightness_multipliers: Array[float] = [1.0]
	floor_spill_light.apply_mask(surfaces, brightness_multipliers)


# --- Текстура и 2.5D-глубины ---

func create_spot_texture() -> void:
	# Генерация пятна вынесена в LightMaskBuilder.
	original_spot = LightMaskBuilder.create_spot_image()

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


# Условная глубина плоскости поверхности для 2.5D-проекции.
# Задняя стена — линия стыка с полом, мебель — эффективная
# глубина препятствия, остальное — глубина комнаты.
func get_surface_depth(surface: LightSurface) -> float:
	if surface == null:
		return 0.0

	if surface == backwall_surface:
		return get_backwall_floor_y(backwall_surface)

	if desk_caster != null and desk_surfaces.has(surface):
		return desk_caster.get_effective_depth()

	if player_reference != null:
		return player_reference.global_position.y

	return global_position.y


# --- Маски и тени ---

# Общая проверка: отбрасывает ли препятствие тень на поверхность.
# Принимать тени могут только поверхности с receives_shadows() в профиле.
func should_cast_shadow(
	surface: LightSurface,
	shadow_caster: ShadowCasterRef
) -> bool:
	if player_reference == null or shadow_caster == null:
		return false
	if shadow_caster.caster == null:
		return false
	if not surface.receives_shadows():
		return false

	# Здесь Y корней — условная глубина в комнате (на уровне пола).
	var light_depth: float = player_reference.global_position.y
	var obstacle_depth: float = shadow_caster.get_depth()
	var wall_depth: float = get_backwall_floor_y(surface)

	# Для проекции препятствие должно лежать между игроком и задней стеной.
	return (
		light_depth > obstacle_depth + maxf(shadow_caster.depth_tolerance, 1.0)
		and obstacle_depth > wall_depth + 1.0
	)


# Полигоны тени одного препятствия через обобщённый проектор.
# Препятствие описывается данными (ShadowCasterRef), сама математика
# находится в ShadowProjector2_5D и не зависит от типа объекта.
func project_caster_shadow_polygons(
	shadow_caster: ShadowCasterRef,
	light_world: Vector2,
	wall_depth: float,
	receiver: Node2D
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if shadow_caster == null or shadow_caster.caster == null:
		return result
	if player_reference == null:
		return result

	return ShadowProjector2_5D.project_polygons(
		shadow_caster.caster,
		light_world,
		player_reference.global_position.y,
		shadow_caster.get_effective_depth(),
		wall_depth,
		receiver
	)


# Публичная обёртка сохранена для совместимости с текущей архитектурой.
func update_surface_mask(surface: LightSurface, light_world: Vector2) -> void:
	update_mask_for_light(surface, light_world, self, clipped_spot, false)


# Генератор маски одинаковый для основного источника и света на стене.
# Сборка Image и кэширование выполняет LightMaskBuilder. Расчёты 2.5D
# теней стола и торшера остаются здесь и передаются строителю лениво
# через build_shadow_polygons(): полигоны строятся только при реальной
# пересборке маски.
func update_mask_for_light(
	surface: LightSurface,
	light_world: Vector2,
	receiver: PointLight2D,
	mask_image: Image,
	wall_pass: bool
) -> void:
	var current_desk_transform: Transform2D = Transform2D.IDENTITY
	if desk_reference != null:
		current_desk_transform = desk_reference.global_transform
	var current_lamp_transform: Transform2D = Transform2D.IDENTITY
	if lamp_reference != null:
		current_lamp_transform = lamp_reference.global_transform

	var mask_rebuilt: bool = mask_builder.update_mask(
		surface,
		light_world,
		receiver,
		mask_image,
		original_spot,
		wall_pass,
		get_shadow_state(surface),
		desk_shadow_strength,
		current_desk_transform,
		current_lamp_transform,
		build_shadow_polygons
	)
	if not mask_rebuilt:
		return

	# Сохраняем тот же ImageTexture/RID и обновляем пиксели маски.
	LightMaskBuilder.upload_mask(receiver, mask_image)


# Состояние теней для кэша строителя: бит 0 — тень стола, бит 1 — торшера.
func get_shadow_state(surface: LightSurface) -> int:
	var state: int = 0
	if should_cast_shadow(surface, desk_caster):
		state += 1
	if should_cast_shadow(surface, lamp_caster):
		state += 2
	return state


# Ленивый поставщик полигонов теней для LightMaskBuilder.update_mask().
func build_shadow_polygons(
	surface: LightSurface,
	light_world: Vector2,
	receiver: PointLight2D
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var shadow_state: int = get_shadow_state(surface)
	var wall_floor_y: float = get_backwall_floor_y(surface)

	if (shadow_state & 1) != 0:
		result.append_array(
			project_caster_shadow_polygons(
				desk_caster,
				light_world,
				wall_floor_y,
				receiver
			)
		)
	if (shadow_state & 2) != 0:
		result.append_array(
			project_caster_shadow_polygons(
				lamp_caster,
				light_world,
				wall_floor_y,
				receiver
			)
		)

	return result


# --- Публичный API ---

# Поверхность под точкой мира: мебель проверяется первой.
func find_surface(world_point: Vector2) -> LightSurface:
	for desk_surface in desk_surfaces:
		if desk_surface.receives_light() and desk_surface.contains_world_point(world_point):
			return desk_surface

	for surface in surfaces:
		if surface.receives_light() and surface.contains_world_point(world_point):
			return surface

	return null

# Скрытые надписи учитывают основной свет и все дополнительные проходы.
func get_light_strength_at(world_point: Vector2) -> float:
	if not is_visible_in_tree():
		return 0.0
	if not is_instance_valid(flashlight) or not flashlight.is_equipped:
		return 0.0

	var strength: float = 0.0
	if enabled:
		strength = LightPass.sample_strength(self, clipped_spot, world_point)
	if is_instance_valid(wall_shadow_light):
		strength = maxf(
			strength,
			wall_shadow_light.get_strength_at(world_point)
		)
	if is_instance_valid(floor_spill_light):
		strength = maxf(
			strength,
			floor_spill_light.get_strength_at(world_point)
		)
	strength = maxf(
		strength,
		light_pass_manager.get_strength_at(world_point)
	)
	return strength


# Оставляем принятую ранее 2.5D-логику выбора точки попадания:
# луч "прилипает" к ближайшему пересечению с поверхностью стола.
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

	return _get_ray_desk_intersection(
		from_world,
		to_world,
		ray_direction.normalized()
	)


# Ближайшее к лучу пересечение с полигонами стола.
func _get_ray_desk_intersection(
	from_world: Vector2,
	to_world: Vector2,
	direction: Vector2
) -> Vector2:
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

			var candidate: Vector2 = intersection + direction * 2.0
			if not desk_surface.contains_world_point(candidate):
				continue

			var distance_sq: float = from_world.distance_squared_to(candidate)
			if distance_sq < nearest_distance_sq:
				nearest_distance_sq = distance_sq
				nearest_position = candidate

	return nearest_position

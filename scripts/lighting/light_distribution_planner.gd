
class_name LightDistributionPlanner
extends RefCounted


# Принимает решения о распределении света между поверхностями.
# Не создаёт текстур и не управляет PointLight2D: планирование
# отделено от исполнения (LightPass / будущий LightPassManager).
#
# Источники поведения:
#  - профили поверхностей (LightSurfaceProfile): что собой
#    представляет каждая поверхность;
#  - связи (LightSurfaceConnection): как свет переходит между
#    двумя конкретными плоскостями.


var _connections: Array[LightSurfaceConnection] = []
var _plan: LightDistributionPlan = LightDistributionPlan.new()


# Данные одного кадра, необходимые для 2.5D-проекции.
# Заполняется SurfaceSpot до вызова build_plan().
class ProjectionContext:
	# Точка источника света в мировых координатах.
	var light_world: Vector2

	# Условная глубина источника света (обычно Y игрока).
	var light_depth: float = 0.0

	# Точка попадания основного луча на основную поверхность.
	var target: Vector2 = Vector2.ZERO

	# Диаметр основного пятна.
	var source_diameter: float = 0.0

	var near_distance: float = 0.0
	var far_distance: float = 0.0
	var near_energy: float = 0.0
	var far_energy: float = 0.0

	# Возвращает условную глубину плоскости поверхности.
	var resolve_depth: Callable

	# Проверяет, отбрасывает ли препятствие тень на поверхность.
	var shadow_check: Callable


func set_connections(connections: Array[LightSurfaceConnection]) -> void:
	_connections.clear()

	for connection in connections:
		if connection != null:
			_connections.append(connection)


func get_last_plan() -> LightDistributionPlan:
	return _plan


# Формирует план освещения: основная поверхность + все затронутые
# соседи. Возвращает тот же экземпляр плана (переиспользуется
# между кадрами).
func build_plan(
	light_node: PointLight2D,
	primary_surface: LightSurface,
	intersections: Array[LightSurface],
	projection_context: ProjectionContext = null
) -> LightDistributionPlan:
	_plan.clear()

	if not is_instance_valid(light_node) or not is_instance_valid(primary_surface):
		return _plan

	for surface in intersections:
		if not is_instance_valid(surface):
			continue

		if not surface.receives_light():
			continue

		var entry: LightDistributionPlan.LightDistributionEntry = \
				LightDistributionPlan.LightDistributionEntry.new()
		entry.surface = surface
		entry.is_primary = surface == primary_surface
		entry.light_group = surface.get_light_group()
		entry.receives_shadows = surface.receives_shadows()
		entry.brightness_multiplier = surface.get_brightness_multiplier()
		entry.size_multiplier = 1.0

		if entry.is_primary:
			# Основная поверхность: проекция и яркость определяются
			# её собственным профилем.
			entry.projection_mode = surface.get_projection_mode()
			_plan.add_entry(entry)
		elif _resolve_transition(primary_surface, surface, entry, projection_context):
			_plan.add_entry(entry)

	return _plan


# Определяет способ перехода света source -> receiver по связи
# или по совместимости профилей, заполняя параметры записи.
func resolve_projection(
	source: LightSurface,
	receiver: LightSurface
) -> LightSurfaceProfile.ProjectionMode:
	var connection: LightSurfaceConnection = find_connection(source, receiver)

	if connection != null:
		return connection.projection_mode

	# Без явной связи: экранная проекция работает только между
	# совместимыми поверхностями ROOM-группы.
	if source.get_projection_mode() == LightSurfaceProfile.ProjectionMode.SCREEN_SPACE \
			and receiver.get_projection_mode() == LightSurfaceProfile.ProjectionMode.SCREEN_SPACE \
			and source.get_light_group() == receiver.get_light_group():
		return LightSurfaceProfile.ProjectionMode.SCREEN_SPACE

	return receiver.get_projection_mode()


# Учитывает ограничения видимости: блокировку света, связи и
# условную глубину. Возвращает true, если свет на получателя
# допустим. Полная логика перекрытия (blocks_light) пока не
# реализована — здесь точка расширения для неё.
func evaluate_visibility(
	source: LightSurface,
	receiver: LightSurface
) -> bool:
	if not receiver.receives_light():
		return false

	var connection: LightSurfaceConnection = find_connection(source, receiver)

	# Между поверхностями без связи свет переходит только
	# при совместимой экранной проекции в одной группе.
	if connection == null:
		return source.get_projection_mode() \
				== LightSurfaceProfile.ProjectionMode.SCREEN_SPACE \
			and receiver.get_projection_mode() \
				== LightSurfaceProfile.ProjectionMode.SCREEN_SPACE \
			and source.get_light_group() == receiver.get_light_group()

	return true


# Ищет связь для пары поверхностей (в любом направлении).
func find_connection(
	surface_a: LightSurface,
	surface_b: LightSurface
) -> LightSurfaceConnection:
	for connection in _connections:
		if connection.matches_pair(surface_a, surface_b):
			return connection

	return null


# Заполняет запись для соседней поверхности на основе связи.
# Возвращает false, если свет на поверхность попадать не должен.
func _resolve_transition(
	source: LightSurface,
	receiver: LightSurface,
	entry: LightDistributionPlan.LightDistributionEntry,
	projection_context: ProjectionContext
) -> bool:
	if not evaluate_visibility(source, receiver):
		return false

	var connection: LightSurfaceConnection = find_connection(source, receiver)

	entry.projection_mode = resolve_projection(source, receiver)

	if connection != null:
		if not connection.allows_direction(source, receiver):
			# Связь есть, но направление запрещено.
			return false

		# Множители зависят от направления перехода.
		var forward: bool = String(source.name) == connection.surface_a_name
		if forward:
			entry.brightness_multiplier = connection.brightness_multiplier
			entry.size_multiplier = connection.size_multiplier
		else:
			entry.brightness_multiplier = connection.reverse_brightness_multiplier
			entry.size_multiplier = connection.reverse_size_multiplier

		entry.receives_shadows = connection.casts_shadow_on_transition \
				and receiver.receives_shadows()

		if entry.projection_mode \
				== LightSurfaceProfile.ProjectionMode.PROJECTED_2_5D:
			var projected_ok: bool = _apply_projection(
				entry,
				source,
				projection_context
			)

			# Яркость профиля поверхности идёт в маску получателя
			# (как в старом update_desk_spill_mask); энергия уже
			# рассчитана в _apply_projection по множителю связи.
			if projected_ok and not entry.receives_shadows:
				entry.brightness_multiplier = \
						receiver.get_brightness_multiplier()

			return projected_ok
	else:
		# Совместимая экранная проекция: параметры из профиля.
		entry.brightness_multiplier = receiver.get_brightness_multiplier()

	return true


# Рассчитывает параметры PROJECTED_2_5D для записи: позицию,
# масштаб и энергию пятна на поверхности-получателе.
# Возвращает false, если проекция невозможна или пятно выходит
# за пределы получателя.
func _apply_projection(
	entry: LightDistributionPlan.LightDistributionEntry,
	source: LightSurface,
	context: ProjectionContext
) -> bool:
	if context == null:
		return false

	var source_depth: float = context.resolve_depth.call(source)
	var target_depth: float = context.resolve_depth.call(entry.surface)

	var projection: Dictionary = LightProjection2_5D.project_point(
		context.light_world,
		context.target,
		context.light_depth,
		source_depth,
		target_depth
	)

	if projection.is_empty():
		return false

	var projected_point: Vector2 = projection["point"]
	var factor: float = projection["factor"]

	# Направление проверяется как в исходной логике:
	#  - получатель БЛИЖЕ к свету, чем источник (стена -> мебель):
	#    коэффициент обязан быть строго 0..1;
	#  - получатель ДАЛЬШЕ (мебель -> стена): экстраполяция
	#    разрешена, ограничение только снизу (уже в project_point).
	if target_depth > source_depth and factor >= 1.0:
		return false

	# Строгая проверка точки — только для получателей с тенями
	# (старый код проверял contains_world_point лишь для стены).
	# Для остальных получателей видимость определяет маска:
	# свет показывается только на их полигонах под пятном.
	if entry.receives_shadows \
			and not entry.surface.contains_world_point(projected_point):
		return false

	# Перспективные тени возможны, только если препятствие лежит
	# между источником и получателем.
	if entry.receives_shadows and context.shadow_check.is_valid():
		if not context.shadow_check.call(entry.surface):
			return false

	var distance: float = context.light_world.distance_to(projected_point)
	var distance_ratio: float = clampf(
		(distance - context.near_distance)
			/ maxf(context.far_distance - context.near_distance, 1.0),
		0.0,
		1.0
	)
	var diameter: float = context.source_diameter * factor * entry.size_multiplier

	# Форма пятна: получатели с тенями (стена) используют spot_shape
	# своей поверхности; мебельные получатели — равномерный масштаб
	# (как в старом DeskSpillSpot: спроецированное пятно круглое).
	var scale_base: Vector2 = entry.surface.get_spot_shape() \
			if entry.receives_shadows else Vector2.ONE

	entry.spot_position = projected_point
	entry.spot_scale = scale_base * (diameter / float(LightMaskBuilder.SPOT_RESOLUTION))
	entry.energy_override = lerpf(
		context.near_energy,
		context.far_energy,
		distance_ratio
	) * entry.brightness_multiplier

	return true


class_name LightPassManager
extends RefCounted


# Применяет план распределения света (LightDistributionPlan)
# к световым проходам (LightPass). Исполнитель: не принимает
# решений, а только настраивает проходы по записям плана.
#
# Поддержаны SCREEN_SPACE-записи групп ROOM и FURNITURE:
#  - ROOM — переходы стен/потолка/пола (Z-диапазон комнаты);
#  - FURNITURE — переходы с мебелью (Z-диапазон деталей).
# Пара Backwall <-> Floor и переходы Backwall <-> Desk остаются
# на старых механизмах и исключаются попарно через
# set_excluded_pairs().


# Пул проходов по группам: каждой группе соответствует один
# общий проход со своим Z-диапазоном. Совместимые записи
# объединяются в него.
var _pool_by_group: Dictionary = {}

# Отдельные проходы для PROJECTED_2_5D-записей: у каждой своё
# положение пятна (в отличие от экранного продолжения).
var _projected_pool: Array[LightPass] = []
var _projected_count: int = 0

var _owner_node: Node2D
var _spot_image: Image
var _light_color: Color
var _wall_pass: LightPass

# Пока переходы Backwall <-> Floor обслуживают старые
# специализированные механизмы (FloorSpillSpot / wall_from_floor).
# Исключение попарное: Floor <-> LeftWall уже работает через план.
var _excluded_pairs: Array[PackedStringArray] = []

# Обработчик записей, принимающих перспективные тени
# (сигнатура SurfaceSpot.update_mask_for_light).
var _shadow_handler: Callable


func initialize(
	owner_node: Node2D,
	spot_image: Image,
	light_color: Color,
	wall_pass: LightPass
) -> void:
	_owner_node = owner_node
	_spot_image = spot_image
	_light_color = light_color
	_wall_pass = wall_pass


func set_excluded_pairs(pairs: Array[PackedStringArray]) -> void:
	_excluded_pairs = pairs.duplicate()


# Пара совпадает с исключённой в любом порядке направлений.
func _is_excluded_pair(surface_a: LightSurface, surface_b: LightSurface) -> bool:
	var name_a: String = String(surface_a.name)
	var name_b: String = String(surface_b.name)

	for pair in _excluded_pairs:
		if (pair[0] == name_a and pair[1] == name_b) \
				or (pair[0] == name_b and pair[1] == name_a):
			return true

	return false


func set_shadow_handler(handler: Callable) -> void:
	_shadow_handler = handler


# Z-диапазон прохода определяется логической группой поверхности:
# мебель освещается на уровне деталей (Z=1), комната — на уровне
# фона и пола.
func _get_group_z_range(group: LightSurfaceProfile.LightGroup) -> Vector2i:
	match group:
		LightSurfaceProfile.LightGroup.FURNITURE:
			return Vector2i(1, 1)
		_:
			return Vector2i(-1024, 0)


# Выдаёт общий проход группы, создавая его при необходимости.
func _get_group_pass(
	group: LightSurfaceProfile.LightGroup
) -> LightPass:
	if _pool_by_group.has(group):
		return _pool_by_group[group]

	var light_pass: LightPass = LightPass.new()
	var z_range: Vector2i = _get_group_z_range(group)
	_owner_node.add_child(light_pass)
	light_pass.setup(
		"PlanPass_%s" % LightSurfaceProfile.LightGroup.keys()[group],
		_light_color,
		z_range.x,
		z_range.y
	)
	light_pass.init_mask(_spot_image)
	_pool_by_group[group] = light_pass
	return light_pass


# Выдаёт проход для проекционной записи, создавая при
# необходимости. Проходы переиспользуются между кадрами.
func _get_projected_pass(z_range: Vector2i) -> LightPass:
	if _projected_count < _projected_pool.size():
		return _projected_pool[_projected_count]

	var light_pass: LightPass = LightPass.new()
	_owner_node.add_child(light_pass)
	light_pass.setup(
		"PlanPass_Projected_%d" % _projected_pool.size(),
		_light_color,
		z_range.x,
		z_range.y
	)
	light_pass.init_mask(_spot_image)
	_projected_pool.append(light_pass)
	return light_pass


func reset() -> void:
	for group in _pool_by_group:
		var light_pass: LightPass = _pool_by_group[group]
		if is_instance_valid(light_pass):
			light_pass.reset_pass()

	for light_pass in _projected_pool:
		if is_instance_valid(light_pass):
			light_pass.reset_pass()

	_projected_count = 0


func get_strength_at(world_point: Vector2) -> float:
	var strength: float = 0.0

	for group in _pool_by_group:
		var light_pass: LightPass = _pool_by_group[group]
		if is_instance_valid(light_pass):
			strength = maxf(strength, light_pass.get_strength_at(world_point))

	for light_pass in _projected_pool:
		if is_instance_valid(light_pass):
			strength = maxf(strength, light_pass.get_strength_at(world_point))

	return strength


# Раскладывает план по проходам. Экранные ROOM-записи без теней
# объединяются в один общий проход; записи с тенями направляются
# в настенный проход через обработчик масок.
func apply_plan(
	main_spot: PointLight2D,
	plan: LightDistributionPlan,
	light_origin: Vector2,
	base_energy: float
) -> void:
	reset()

	if not is_instance_valid(main_spot) or base_energy <= 0.001:
		return

	var primary: LightDistributionPlan.LightDistributionEntry = \
			plan.get_primary_entry()

	# Переходы работают от основной поверхности с экранной
	# проекцией. Пол (ROOM) и мебель (FURNITURE) — обе
	# допустимые основные поверхности.
	if primary == null:
		return

	if primary.projection_mode != LightSurfaceProfile.ProjectionMode.SCREEN_SPACE:
		return

	# Совместимые экранные записи группируются по Z-группе:
	# каждой группе соответствует один общий проход.
	# Проекционные записи (PROJECTED_2_5D) собираются отдельно.
	var grouped: Dictionary = {}
	var projected: Dictionary = {}

	for entry in plan.entries:
		if entry.is_primary:
			continue

		if not is_instance_valid(entry.surface):
			continue

		if _is_excluded_pair(primary.surface, entry.surface):
			continue

		if entry.light_group == LightSurfaceProfile.LightGroup.SPECIAL:
			continue

		if entry.receives_shadows \
				and entry.projection_mode \
					== LightSurfaceProfile.ProjectionMode.SCREEN_SPACE:
			_apply_shadow_entry(entry, main_spot, light_origin, base_energy)
			continue

		if entry.projection_mode \
				== LightSurfaceProfile.ProjectionMode.PROJECTED_2_5D:
			if entry.energy_override <= 0.001:
				continue

			var projected_bucket: Dictionary = projected.get_or_add(
				entry.light_group,
				{
					"surfaces": [],
					"brightness": [],
					"first_entry": entry
				}
			)
			projected_bucket["surfaces"].append(entry.surface)
			projected_bucket["brightness"].append(entry.brightness_multiplier)
			continue

		var bucket: Dictionary = grouped.get_or_add(
			entry.light_group,
			{
				"surfaces": [],
				"brightness": []
			}
		)
		bucket["surfaces"].append(entry.surface)
		bucket["brightness"].append(entry.brightness_multiplier)

	# Маска содержит только соседние поверхности, без основной.
	for group in grouped:
		var bucket: Dictionary = grouped[group]

		var bucket_surfaces: Array[LightSurface] = []
		var bucket_brightness: Array[float] = []

		for surface in bucket["surfaces"]:
			bucket_surfaces.append(surface)

		for value in bucket["brightness"]:
			bucket_brightness.append(value)

		var group_pass: LightPass = _get_group_pass(group)
		group_pass.global_transform = main_spot.global_transform
		group_pass.energy = base_energy
		group_pass.apply_mask(bucket_surfaces, bucket_brightness)
		group_pass.enabled = true

	# Проекционные записи: у каждой группы своё положение пятна.
	for group in projected:
		var bucket: Dictionary = projected[group]
		var first_entry: LightDistributionPlan.LightDistributionEntry = \
				bucket["first_entry"]

		var bucket_surfaces: Array[LightSurface] = []
		var bucket_brightness: Array[float] = []

		for surface in bucket["surfaces"]:
			bucket_surfaces.append(surface)

		for value in bucket["brightness"]:
			bucket_brightness.append(value)

		# Несколько поверхностей в одной маске-union: перекрытия
		# полигонов на стыках берутся по максимуму яркости и
		# выделяются полосой. Выравниваем яркость до единой, чтобы
		# стыки (Top/Front) были неотличимы от остальной поверхности.
		if bucket_brightness.size() > 1:
			var uniform_brightness: float = bucket_brightness.max()
			bucket_brightness.clear()
			for surface in bucket_surfaces:
				bucket_brightness.append(uniform_brightness)

		var projected_pass: LightPass = _get_projected_pass(
			_get_group_z_range(group)
		)
		_projected_count += 1

		# Проход переиспользуется между кадрами и группами: Z-диапазон
		# обязан соответствовать текущей группе, иначе свет с диапазоном
		# стены не осветит мебель (и наоборот).
		var z_range: Vector2i = _get_group_z_range(group)
		projected_pass.range_z_min = z_range.x
		projected_pass.range_z_max = z_range.y

		# Поворот: получатель с тенями (стена) использует свой
		# spot_rotation; мебельные получатели — поворот основного
		# луча (как в старом update_desk_from_wall_light).
		if bucket_surfaces.size() == 1 and first_entry.receives_shadows:
			projected_pass.global_rotation = deg_to_rad(
				first_entry.surface.get_spot_rotation_degrees()
			)
		else:
			projected_pass.global_rotation = main_spot.global_rotation

		projected_pass.global_position = first_entry.spot_position
		projected_pass.scale = first_entry.spot_scale
		projected_pass.energy = first_entry.energy_override

		# Одна поверхность с перспективными тенями (например,
		# Backwall за столом) — маску с тенями строит обработчик.
		if bucket_surfaces.size() == 1 and first_entry.receives_shadows \
				and _shadow_handler.is_valid():
			_shadow_handler.call(
				first_entry.surface,
				light_origin,
				projected_pass,
				projected_pass.mask_image,
				true
			)
		else:
			# Несколько поверхностей с одинаково спроецированным
			# пятном (например, детали стола) — общая маска без
			# перспективных теней.
			projected_pass.apply_mask(bucket_surfaces, bucket_brightness)

		projected_pass.enabled = true

# Запись с тенью направляется в настенный проход. Backwall уже
# принимает тени через WallShadowSpot: второй источник поверх
# него не создаётся.
func _apply_shadow_entry(
	entry: LightDistributionPlan.LightDistributionEntry,
	main_spot: PointLight2D,
	light_origin: Vector2,
	base_energy: float
) -> void:
	if not is_instance_valid(_wall_pass) or not _shadow_handler.is_valid():
		return

	_wall_pass.global_transform = main_spot.global_transform
	_wall_pass.energy = base_energy * entry.brightness_multiplier

	if _wall_pass.energy > 0.001:
		_shadow_handler.call(
			entry.surface,
			light_origin,
			_wall_pass,
			_wall_pass.mask_image,
			true
		)

		_wall_pass.enabled = true

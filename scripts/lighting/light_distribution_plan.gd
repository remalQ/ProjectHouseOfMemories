
class_name LightDistributionPlan
extends RefCounted


# Промежуточный набор данных: результаты всех решений о
# распределении света, принятых до отрисовки. Планировщик
# (LightDistributionPlanner) формирует план, исполнитель
# (в будущем LightPassManager) применяет его к световым проходам.
# План ничего не знает о PointLight2D и текстурах.


# Одна запись плана: как осветить одну поверхность-получатель.
class LightDistributionEntry:
	# Поверхность-получатель света.
	var surface: LightSurface

	# Способ проекции пятна на эту поверхность.
	var projection_mode: LightSurfaceProfile.ProjectionMode = \
			LightSurfaceProfile.ProjectionMode.SCREEN_SPACE

	# Логическая Z-группа: определяет диапазон Z светового прохода.
	var light_group: LightSurfaceProfile.LightGroup = \
			LightSurfaceProfile.LightGroup.ROOM

	# Является ли поверхность основной целью луча.
	var is_primary: bool = false

	# Множитель яркости относительно основного пятна.
	var brightness_multiplier: float = 1.0

	# Множитель размера пятна.
	var size_multiplier: float = 1.0

	# Принимает ли поверхность перспективные тени в этой записи.
	var receives_shadows: bool = false

	# Связь, по которой свет попал на поверхность (null для основной).
	var connection: LightSurfaceConnection

	# --- Параметры PROJECTED_2_5D (заполняет планировщик) ---

	# Абсолютная позиция пятна на поверхности-получателе.
	# Действительна, только если energy_override > 0.
	var spot_position: Vector2 = Vector2.ZERO

	# Абсолютный масштаб пятна (учитывает форму поверхности).
	var spot_scale: Vector2 = Vector2.ONE

	# Абсолютная энергия прохода. Отрицательное значение означает,
	# что у записи нет собственной проекции.
	var energy_override: float = -1.0


var entries: Array[LightDistributionEntry] = []


func add_entry(entry: LightDistributionEntry) -> void:
	entries.append(entry)


# Основная поверхность попадания луча, если она есть в плане.
func get_primary_entry() -> LightDistributionEntry:
	for entry in entries:
		if entry.is_primary:
			return entry

	return null


# Все записи с заданным способом проекции.
func get_entries_by_projection(
	mode: LightSurfaceProfile.ProjectionMode
) -> Array[LightDistributionEntry]:
	var result: Array[LightDistributionEntry] = []

	for entry in entries:
		if entry.projection_mode == mode:
			result.append(entry)

	return result


# Все записи заданной логической группы (ROOM, FURNITURE...).
func get_entries_by_group(
	group: LightSurfaceProfile.LightGroup
) -> Array[LightDistributionEntry]:
	var result: Array[LightDistributionEntry] = []

	for entry in entries:
		if entry.light_group == group:
			result.append(entry)

	return result


func is_empty() -> bool:
	return entries.is_empty()


func clear() -> void:
	entries.clear()

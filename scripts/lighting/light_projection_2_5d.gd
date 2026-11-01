
class_name LightProjection2_5D
extends RefCounted


# Проекция светового пятна между условными плоскостями глубины.
# Универсальный математический инструмент: не знает ни о столе,
# ни о стенах — только о глубинах и точках.
#
# Используется планировщиком (LightDistributionPlanner) для
# расчёта записей плана с PROJECTED_2_5D. Тот же расчёт, что
# применяли update_wall_shadow_light (стол -> стена) и
# update_desk_from_wall_light (стена -> стол), поэтому свет
# и тени остаются согласованными.


# Проецирует точку target (лежащую на плоскости source_depth)
# на плоскость target_depth. Возвращает словарь:
#   "point"  — проецированная точка (Vector2),
#   "factor" — коэффициент проекции 0..1 (float).
# При невозможности проекции возвращает пустой словарь.
static func project_point(
	light_world: Vector2,
	target: Vector2,
	light_depth: float,
	source_depth: float,
	target_depth: float
) -> Dictionary:
	var depth_span: float = light_depth - source_depth
	if depth_span <= 1.0:
		return {}

	var factor: float = (light_depth - target_depth) / depth_span
	if factor <= 0.0:
		return {}

	var light_height: float = light_depth - light_world.y
	var target_height: float = source_depth - target.y
	var projected_height: float = (
		light_height + (target_height - light_height) * factor
	)

	var projected_point: Vector2 = Vector2(
		light_world.x + (target.x - light_world.x) * factor,
		target_depth - projected_height
	)

	return {
		"point": projected_point,
		"factor": factor
	}

class_name ShadowProjector2_5D
extends RefCounted


# Обобщённая 2.5D-проекция теней.
#
# Экранные координаты переводятся в условные (X, глубина, высота):
# высота точки = глубина её основания минус экранный Y. Луч из линзы
# через силуэт препятствия пересекает плоскость приёмника — так
# получаются полигоны тени для световой маски.
#
# Раньше эта математика дублировалась в SurfaceSpot отдельно для стола
# и торшера; теперь препятствия описываются данными (ShadowCasterRef
# в surface_spot.gd), а проекция не знает, ЧТО отбрасывает тень.


# Проецирует полигоны силуэтов из caster на плоскость приёмника.
# light_world    — точка, из которой выходит свет (линза фонарика);
# light_depth    — условная глубина источника света;
# obstacle_depth — эффективная глубина препятствия (с учётом bias);
# receiver_depth — глубина плоскости, на которую ложится тень;
# receiver       — узел, в локальные координаты которого переводится
#                  результат (приёмник света или строитель масок).
static func project_polygons(
	caster: Node2D,
	light_world: Vector2,
	light_depth: float,
	obstacle_depth: float,
	receiver_depth: float,
	receiver: Node2D
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []

	var depth_difference: float = light_depth - obstacle_depth
	if depth_difference <= 1.0:
		return result

	var projection_factor: float = (
		(light_depth - receiver_depth)
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
			var obstacle_world: Vector2 = shape.to_global(
				vertex + shape.offset
			)

			# Высота препятствия относительно его эффективной глубины.
			var obstacle_height: float = (
				obstacle_depth - obstacle_world.y
			)

			var projected_x: float = (
				light_world.x
				+ (obstacle_world.x - light_world.x) * projection_factor
			)

			var projected_height: float = (
				light_height
				+ (obstacle_height - light_height) * projection_factor
			)

			var projected_y: float = receiver_depth - projected_height

			projected_polygon.append(
				receiver.to_local(Vector2(projected_x, projected_y))
			)

		result.append(projected_polygon)

	return result

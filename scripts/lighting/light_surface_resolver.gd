
class_name LightSurfaceResolver
extends RefCounted


# Выбирает поверхности, которые затронуты светом.
# Геометрия пересечений остаётся в LightMaskBuilder;
# построение масок и управление PointLight2D — в других классах.
var _registered_surfaces: Array[LightSurface] = []
var _intersections: Array[LightSurface] = []


func register_surfaces(
	room_surfaces: Array[LightSurface],
	furniture_surfaces: Array[LightSurface]
) -> void:
	_registered_surfaces.clear()

	for surface in room_surfaces:
		_register(surface)

	for surface in furniture_surfaces:
		_register(surface)


func _register(surface: LightSurface) -> void:
	if is_instance_valid(surface) and not _registered_surfaces.has(surface):
		_registered_surfaces.append(surface)


func reset() -> void:
	_intersections.clear()


func resolve(light_node: PointLight2D) -> void:
	_intersections.clear()

	if not is_instance_valid(light_node):
		return

	_intersections = LightMaskBuilder.find_spot_intersections(
		light_node,
		_registered_surfaces
	)


func get_intersections() -> Array[LightSurface]:
	return _intersections.duplicate()

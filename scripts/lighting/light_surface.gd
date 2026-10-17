class_name LightSurface
extends Polygon2D

@export var spot_shape: Vector2 = Vector2.ONE
@export var spot_rotation_degrees: float = 0.0
@export var brightness_multiplier: float = 1.0


func _ready() -> void:
	# Скрываем заливку, но сохраняем разметку.
	hide()


func contains_world_point(world_point: Vector2) -> bool:
	var local_point: Vector2 = to_local(world_point) - offset

	return Geometry2D.is_point_in_polygon(
		local_point,
		polygon
	)

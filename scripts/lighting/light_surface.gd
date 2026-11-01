
class_name LightSurface
extends Polygon2D


# Существующие параметры.
# Сохраняем для совместимости с SurfaceSpot.

@export var spot_shape: Vector2 = Vector2.ONE
@export var spot_rotation_degrees: float = 0.0
@export var brightness_multiplier: float = 1.0


# Новый профиль поверхности.
# Отличные от умолчаний значения профиля применяются в расчётах света
# вместо полей выше; поверхности без профиля работают по-старому.

@export_group("Lighting Profile")
@export var light_profile: LightSurfaceProfile


func _ready() -> void:
	# Скрываем заливку, но сохраняем геометрию.
	hide()


func contains_world_point(world_point: Vector2) -> bool:
	var local_point: Vector2 = to_local(world_point) - offset

	return Geometry2D.is_point_in_polygon(
		local_point,
		polygon
	)


# --- Поведение света: профиль имеет приоритет над полями поверхности. ---
# Правило приоритета: применяются только значения профиля, отличные от
# умолчаний LightSurfaceProfile. Благодаря этому назначение профиля
# не сбрасывает параметры, настроенные в сцене (например, форму пятна
# на столешнице в desk.tscn).


# Может ли поверхность получать свет.
# Используется при поиске поверхности под лучом фонарика.
func receives_light() -> bool:
	if light_profile != null:
		return light_profile.receives_light

	return true


# Может ли поверхность принимать проецируемые тени.
func receives_shadows() -> bool:
	if light_profile != null:
		return light_profile.receives_shadows

	return false


# Участвует ли поверхность в перекрытии луча.
func blocks_light() -> bool:
	if light_profile != null:
		return light_profile.blocks_light

	return false


# Форма светового пятна.
func get_spot_shape() -> Vector2:
	if light_profile != null and light_profile.spot_shape != LightSurfaceProfile.DEFAULT_SPOT_SHAPE:
		return light_profile.spot_shape

	return spot_shape


# Поворот пятна в градусах.
func get_spot_rotation_degrees() -> float:
	if light_profile != null and not is_equal_approx(
		light_profile.spot_rotation_degrees,
		LightSurfaceProfile.DEFAULT_SPOT_ROTATION_DEGREES
	):
		return light_profile.spot_rotation_degrees

	return spot_rotation_degrees


# Множитель яркости.
func get_brightness_multiplier() -> float:
	if light_profile != null and not is_equal_approx(
		light_profile.brightness_multiplier,
		LightSurfaceProfile.DEFAULT_BRIGHTNESS_MULTIPLIER
	):
		return light_profile.brightness_multiplier

	return brightness_multiplier


# Способ проекции светового пятна.
func get_projection_mode() -> LightSurfaceProfile.ProjectionMode:
	if light_profile != null:
		return light_profile.projection_mode

	return LightSurfaceProfile.ProjectionMode.SCREEN_SPACE


# Группа, к которой относится поверхность.
func get_light_group() -> LightSurfaceProfile.LightGroup:
	if light_profile != null:
		return light_profile.light_group

	return LightSurfaceProfile.LightGroup.ROOM

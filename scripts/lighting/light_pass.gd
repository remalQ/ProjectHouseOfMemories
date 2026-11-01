class_name LightPass
extends PointLight2D


# Один вспомогательный источник света SurfaceSpot: собственная маска
# (Image) и конфигурация диапазона Z. Заменяет повторявшийся код
# создания WallShadowSpot / FloorSpillSpot / DeskSpillSpot.
# Маски строятся через LightMaskBuilder; простые проходы (пол, стол)
# обрезают пятно полигонами поверхностей, проход стены обновляется
# SurfaceSpot через mask_builder.update_mask() с кэшем.


var spot_image: Image
var mask_image: Image

# Сигнатура последней маски apply_mask(): если трансформация,
# набор поверхностей и яркости не изменились — пересборка не нужна.
var _has_mask_signature: bool = false
var _mask_signature_transform: Transform2D = Transform2D.IDENTITY
var _mask_signature_surfaces: Array = []
var _mask_signature_brightness: Array = []


# Создаёт источник со свойствами, общими для всех проходов SurfaceSpot.
# Источник top-level: масштаб и позиция основного света не должны
# влиять на него.
func setup(pass_name: String, light_color: Color, z_min: int, z_max: int) -> void:
	name = pass_name
	set_as_top_level(true)
	enabled = false
	color = light_color
	shadow_enabled = false
	offset = Vector2.ZERO
	texture_scale = 1.0
	range_z_min = z_min
	range_z_max = z_max
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


# Выделяет проходу собственную копию текстуры пятна под маску.
func init_mask(source_spot: Image) -> void:
	spot_image = source_spot
	mask_image = source_spot.duplicate() as Image
	texture = ImageTexture.create_from_image(mask_image)


# Сброс состояния в начале кадра.
func reset_pass() -> void:
	enabled = false


# Простая маска: текстура пятна, обрезанная полигонами поверхностей,
# с яркостью каждой поверхности. Тени здесь не строятся.
func apply_mask(
	surfaces: Array[LightSurface],
	brightness_multipliers: Array[float]
) -> void:
	if mask_image == null or spot_image == null:
		return

	# Пропуск пересборки: неподвижный прицел не должен собирать
	# попиксельную маску каждый кадр.
	var surface_ids: Array = []
	for surface in surfaces:
		surface_ids.append(surface.get_instance_id())

	if _has_mask_signature \
			and global_transform == _mask_signature_transform \
			and _mask_signature_surfaces == surface_ids \
			and _mask_signature_brightness == brightness_multipliers:
		return

	_has_mask_signature = true
	_mask_signature_transform = global_transform
	_mask_signature_surfaces = surface_ids
	_mask_signature_brightness = brightness_multipliers.duplicate()

	var surface_polygons: Array[PackedVector2Array] = []
	for surface in surfaces:
		surface_polygons.append(
			LightMaskBuilder.build_surface_polygon(surface, self)
		)

	var shadow_polygons: Array[PackedVector2Array] = []
	LightMaskBuilder.build_mask(
		mask_image,
		spot_image,
		surface_polygons,
		brightness_multipliers,
		shadow_polygons,
		1.0
	)

	# Не заменяем GPU-текстуру, а обновляем её содержимое на месте.
	LightMaskBuilder.upload_mask(self, mask_image)


# Интенсивность света прохода в мировой точке.
func get_strength_at(world_point: Vector2) -> float:
	if not enabled:
		return 0.0

	return sample_strength(self, mask_image, world_point)


# Та же математика, что раньше была в SurfaceSpot.sample_light_strength:
# мировая точка переводится в пиксель маски с учётом offset и texture_scale.
static func sample_strength(
	light_node: PointLight2D,
	mask: Image,
	world_point: Vector2
) -> float:
	if mask == null:
		return 0.0
	var local_point: Vector2 = light_node.to_local(world_point)
	var texture_point: Vector2 = (
		(local_point - light_node.offset)
		/ maxf(light_node.texture_scale, 0.001)
		+ Vector2(
			float(mask.get_width()),
			float(mask.get_height())
		) * 0.5
	)
	var pixel_x: int = floori(texture_point.x)
	var pixel_y: int = floori(texture_point.y)
	if pixel_x < 0 or pixel_y < 0:
		return 0.0
	if pixel_x >= mask.get_width():
		return 0.0
	if pixel_y >= mask.get_height():
		return 0.0
	return mask.get_pixel(pixel_x, pixel_y).r * light_node.energy

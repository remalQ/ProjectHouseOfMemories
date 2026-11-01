class_name LightMaskBuilder
extends RefCounted


# Единый генератор световых масок для SurfaceSpot и его
# вспомогательных источников (WallShadowSpot, FloorSpillSpot, DeskSpillSpot).
#
# Обязанности:
#  - генерация базовой текстуры светового пятна;
#  - перевод полигонов поверхностей в локальные координаты приёмника;
#  - попиксельная сборка Image маски с учётом яркости поверхностей и теней;
#  - кэширование: маска пересобирается только при изменении входов.
#
# Расчёты 2.5D-теней остаются в SurfaceSpot и передаются сюда лениво
# через Callable — только при реальной пересборке маски.


# Разрешение текстуры светового пятна.
const SPOT_RESOLUTION: int = 128


# Кэш одного прохода. У каждого получателя масок (основной свет,
# настенный проход, проекционные проходы менеджера) свой кэш:
# общий кэш на несколько получателей приводил к тому, что кэш-хит
# одного пропускал пересборку маски другого ("Parameter \"t\" is null"
# маска оставалась чужой).
class MaskPassCache:
	var polygon: PackedVector2Array = PackedVector2Array()
	var light_origin: Vector2 = Vector2.ZERO
	var desk_transform: Transform2D = Transform2D.IDENTITY
	var lamp_transform: Transform2D = Transform2D.IDENTITY
	var shadow_state: int = -1
	var has_value: bool = false


# Кэши по получателям: ключ — instance_id получателя + признак
# настенного прохода.
var _receiver_caches: Dictionary = {}


func _get_cache(receiver: PointLight2D, wall_pass: bool) -> MaskPassCache:
	var key: int = receiver.get_instance_id() * 2 + (1 if wall_pass else 0)

	if not _receiver_caches.has(key):
		_receiver_caches[key] = MaskPassCache.new()

	return _receiver_caches[key]


# Базовая круглая текстура пятна (перенесено из SurfaceSpot).
static func create_spot_image() -> Image:
	var image: Image = Image.create(
		SPOT_RESOLUTION, SPOT_RESOLUTION, false, Image.FORMAT_RGBA8
	)

	for y in range(SPOT_RESOLUTION):
		for x in range(SPOT_RESOLUTION):
			var uv: Vector2 = Vector2(
				float(x) + 0.5,
				float(y) + 0.5
			) / float(SPOT_RESOLUTION)

			var radius: float = (uv - Vector2(0.5, 0.5)).length() * 2.0
			var brightness: float = 1.0 - smoothstep(0.1, 1.0, radius)
			image.set_pixel(
				x, y, Color(brightness, brightness, brightness, 1.0)
			)

	return image


# Полигон поверхности в локальных координатах приёмника света.
static func build_surface_polygon(
	surface: LightSurface,
	receiver: Node2D
) -> PackedVector2Array:
	var local_polygon: PackedVector2Array = PackedVector2Array()
	for vertex in surface.polygon:
		var world_vertex: Vector2 = surface.to_global(vertex + surface.offset)
		local_polygon.append(receiver.to_local(world_vertex))

	return local_polygon


# Грубая проверка: пересекается ли пятно света с поверхностью.
# Сравниваются AABB поверхности и квадрат текстуры в локальных
# координатах приёмника.
static func spot_overlaps_surface(
	light_node: PointLight2D,
	surface: LightSurface
) -> bool:
	var half_size: float = float(SPOT_RESOLUTION) * 0.5
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF

	for vertex in surface.polygon:
		var world_vertex: Vector2 = surface.to_global(vertex + surface.offset)
		var local_vertex: Vector2 = light_node.to_local(world_vertex)
		min_x = minf(min_x, local_vertex.x)
		max_x = maxf(max_x, local_vertex.x)
		min_y = minf(min_y, local_vertex.y)
		max_y = maxf(max_y, local_vertex.y)

	return (
		min_x < half_size
		and max_x > -half_size
		and min_y < half_size
		and max_y > -half_size
	)


# Проверяет реальное пересечение круглой области светового пятна
# с полигоном поверхности.
# Вычисления выполняются в локальных координатах источника света,
# поэтому учитываются его положение, поворот и масштаб.
static func spot_intersects_surface_exact(
	light_node: PointLight2D,
	surface: LightSurface
) -> bool:
	if not is_instance_valid(surface) or not surface.receives_light():
		return false

	if surface.polygon.size() < 3:
		return false

	if is_zero_approx(light_node.scale.x) or is_zero_approx(light_node.scale.y):
		return false

	# Быстрая предварительная проверка.
	if not spot_overlaps_surface(light_node, surface):
		return false

	var local_polygon: PackedVector2Array = build_surface_polygon(surface, light_node)

	var radius: float = float(SPOT_RESOLUTION) * 0.5
	var radius_sq: float = radius * radius

	# Центр светового пятна находится внутри поверхности.
	if Geometry2D.is_point_in_polygon(Vector2.ZERO, local_polygon):
		return true

	for i in range(local_polygon.size()):
		var start: Vector2 = local_polygon[i]
		var end: Vector2 = local_polygon[(i + 1) % local_polygon.size()]

		# Вершина полигона попала внутрь светового пятна.
		if start.length_squared() <= radius_sq:
			return true

		# Проверяем пересечение окружности с ребром полигона.
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(
			Vector2.ZERO, start, end
		)

		if nearest.length_squared() <= radius_sq:
			return true

	return false


# Возвращает все поверхности, пересекаемые основным световым пятном.
# Пока проверяется только геометрическое пересечение в 2D.
# Препятствия, тени и перспективная глубина здесь не учитываются.
static func find_spot_intersections(
	light_node: PointLight2D,
	candidate_surfaces: Array[LightSurface]
) -> Array[LightSurface]:
	var result: Array[LightSurface] = []

	for surface in candidate_surfaces:
		if spot_intersects_surface_exact(light_node, surface):
			result.append(surface)

	return result


# На GL Compatibility ImageTexture.update() не гарантирует обновление
# содержимого light-texture atlas: GPU читает старое пятно, хотя
# ImageTexture.get_image() уже показывает новые пиксели.
# Поэтому каждый новый CPU-образ получит новую текстуру/RID.
# Предыдущие текстуры остаются живыми несколько кадров, чтобы
# renderer не обращался к уже освобождённым atlas entries.
const TEXTURE_RETAIN_FRAMES: int = 8
static var _retained_textures: Array[Dictionary] = []

static func upload_mask(receiver: PointLight2D, mask_image: Image) -> void:
	var previous: Texture2D = receiver.texture
	var replacement: ImageTexture = ImageTexture.create_from_image(mask_image)
	receiver.texture = replacement

	# Удерживать нужно именно заменённые объекты, а не фиксированное
	# количество последних масок: за один кадр может смениться много проходов.
	if previous != null:
		_retained_textures.append({
			"texture": previous,
			"expire_frame": Engine.get_process_frames() + TEXTURE_RETAIN_FRAMES
		})

	var now: int = Engine.get_process_frames()
	var first_alive: int = 0
	while first_alive < _retained_textures.size() \
			and _retained_textures[first_alive]["expire_frame"] <= now:
		first_alive += 1
	if first_alive > 0:
		_retained_textures = _retained_textures.slice(first_alive)


# Попиксельная сборка маски. Точки, попавшие в поверхности, получают
# пиксель пятна с максимальной яркостью среди накрытых поверхностей;
# точки в теневых полигонах дополнительно умножаются на фактор тени.
# Текстуру приёмника НЕ трогает: обновление ImageTexture остаётся
# в ответственности вызывающего кода.
#
# Растеризация сканлайнами: для каждой строки текстуры пересечения
# полигонов с этой строкой считаются по рёбрам (even-odd правило,
# эквивалент is_point_in_polygon), после чего проверка пикселя —
# два сравнения границ спана. Это заменяет is_point_in_polygon
# на каждый пиксель и в разы ускоряет сборку.
static func build_mask(
	mask_image: Image,
	spot_image: Image,
	surface_polygons: Array[PackedVector2Array],
	surface_brightness: Array[float],
	shadow_polygons: Array[PackedVector2Array],
	shadow_strength: float
) -> void:
	var half_size: float = float(SPOT_RESOLUTION) * 0.5
	var shadow_factor: float = 1.0 - clampf(shadow_strength, 0.0, 1.0)

	mask_image.fill(Color.TRANSPARENT)

	for y in range(SPOT_RESOLUTION):
		var row_y: float = float(y) + 0.5 - half_size

		# Спаны поверхностей строки: [x_start, x_end, яркость].
		var spans: Array = []
		for i in range(surface_polygons.size()):
			var polygon_spans: Array = _polygon_spans_at_row(
				surface_polygons[i],
				row_y,
				half_size
			)
			var brightness: float = surface_brightness[i]
			for span in polygon_spans:
				spans.append([span[0], span[1], brightness])

		if spans.is_empty():
			continue

		# Спаны теней строки: [x_start, x_end].
		var shadow_spans: Array = []
		for shadow_polygon in shadow_polygons:
			for span in _polygon_spans_at_row(
					shadow_polygon,
					row_y,
					half_size
			):
				shadow_spans.append([span[0], span[1]])

		var row_start: int = SPOT_RESOLUTION
		var row_end: int = -1
		for span in spans:
			row_start = mini(row_start, span[0])
			row_end = maxi(row_end, span[1])

		for x in range(maxi(row_start, 0), mini(row_end, SPOT_RESOLUTION - 1) + 1):
			var brightness: float = 0.0
			for span in spans:
				if x >= span[0] and x <= span[1] and span[2] > brightness:
					brightness = span[2]

			if brightness <= 0.0:
				continue

			var pixel_color: Color = \
					spot_image.get_pixel(x, y) * brightness

			for shadow_span in shadow_spans:
				if x >= shadow_span[0] and x <= shadow_span[1]:
					pixel_color = Color(
						pixel_color.r * shadow_factor,
						pixel_color.g * shadow_factor,
						pixel_color.b * shadow_factor,
						pixel_color.a * shadow_factor
					)
					break

			mask_image.set_pixel(x, y, pixel_color)


# Спаны полигона на строке row_y (even-odd правило заполнения).
# Возвращает пары пиксельных индексов [x_start, x_end] включительно.
static func _polygon_spans_at_row(
	polygon: PackedVector2Array,
	row_y: float,
	half_size: float
) -> Array:
	var count: int = polygon.size()
	if count < 3:
		return []

	var crossings: Array[float] = []

	for i in range(count):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % count]

		# Строгие неравенства отсекают горизонтальные рёбра
		# и двойный счёт вершин.
		if (a.y <= row_y and b.y > row_y) \
				or (b.y <= row_y and a.y > row_y):
			var t: float = (row_y - a.y) / (b.y - a.y)
			crossings.append(a.x + t * (b.x - a.x))

	if crossings.size() < 2:
		return []

	crossings.sort()

	var spans: Array = []
	for i in range(0, crossings.size() - 1, 2):
		var x_start: int = ceili(crossings[i] + half_size - 0.5)
		var x_end: int = floori(crossings[i + 1] + half_size - 0.5)
		if x_end < 0 or x_start >= SPOT_RESOLUTION:
			continue
		x_start = maxi(0, x_start)
		x_end = mini(SPOT_RESOLUTION - 1, x_end)
		if x_end >= x_start:
			spans.append([x_start, x_end])

	return spans


# Главная точка входа для масок с тенями: пересобирает маску только
# при изменении входов. Полигоны теней запрашиваются у поставщика
# (SurfaceSpot) лениво — после того как кэш подтвердил пересборку.
# shadow_state: бит 0 — тень от стола, бит 1 — тень от торшера.
func update_mask(
	surface: LightSurface,
	light_world: Vector2,
	receiver: PointLight2D,
	mask_image: Image,
	spot_image: Image,
	wall_pass: bool,
	shadow_state: int,
	shadow_strength: float,
	desk_transform: Transform2D,
	lamp_transform: Transform2D,
	shadow_polygons_provider: Callable
) -> bool:
	var cache: MaskPassCache = _get_cache(receiver, wall_pass)

	var local_polygon: PackedVector2Array = (
		build_surface_polygon(surface, receiver)
	)
	var cast_shadow: bool = shadow_state != 0

	# Независимые кэши нужны, чтобы текстура стены не перезаписывала
	# текстуру стола и чтобы повторно не считать неизменную геометрию.
	if cache.has_value:
		var same_surface: bool = local_polygon == cache.polygon
		var same_mode: bool = shadow_state == cache.shadow_state
		var same_source: bool = (
			light_world.distance_squared_to(cache.light_origin) < 0.25
		)
		var same_desk: bool = desk_transform == cache.desk_transform
		var same_lamp: bool = lamp_transform == cache.lamp_transform
		if same_surface and same_mode:
			if not cast_shadow or (
				same_source and same_desk and same_lamp
			):
				return false

	cache.polygon = local_polygon
	cache.light_origin = light_world
	cache.desk_transform = desk_transform
	cache.lamp_transform = lamp_transform
	cache.shadow_state = shadow_state
	cache.has_value = true

	var shadow_polygons: Array[PackedVector2Array] = []
	if cast_shadow and shadow_polygons_provider.is_valid():
		shadow_polygons.append_array(
			shadow_polygons_provider.call(surface, light_world, receiver)
		)

	var surface_polygons: Array[PackedVector2Array] = [local_polygon]
	var surface_brightness: Array[float] = [1.0]

	build_mask(
		mask_image,
		spot_image,
		surface_polygons,
		surface_brightness,
		shadow_polygons,
		shadow_strength
	)

	return true

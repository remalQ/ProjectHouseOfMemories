class_name HandFlashlight
extends Node2D

# Яркость видимого конуса: пятно на поверхности отдельно создаёт SurfaceSpot.
@export_range(0.0, 2.0, 0.01) var beam_energy: float = 0.35
@export var beam_color: Color = Color(1.0, 0.94, 0.78)
@export_range(0.25, 1.25, 0.05) var beam_width_multiplier: float = 0.85

@onready var flashlight_sprite: Sprite2D = $FlashlightSprite
@onready var light_origin: Marker2D = $LightOrigin

var beam: PointLight2D
var is_equipped: bool = false

const BEAM_TEXTURE_WIDTH: int = 384
const BEAM_TEXTURE_HEIGHT: int = 192


func _ready() -> void:
	process_priority = -10

	# Ищем источник по типу, чтобы не зависеть от того,
	# называется узел PointFlashLight2D или PointLight2D.
	for child in light_origin.get_children():
		if child is PointLight2D:
			beam = child as PointLight2D
			break

	if beam == null:
		push_error("HandFlashlight: добавь PointLight2D внутрь LightOrigin.")
		set_process(false)
		return

	create_beam_texture()

	beam.position = Vector2.ZERO
	beam.rotation = 0.0
	beam.offset = Vector2(float(BEAM_TEXTURE_WIDTH) * 0.5, 0.0)
	beam.color = beam_color
	beam.energy = beam_energy
	beam.blend_mode = Light2D.BLEND_MODE_ADD
	beam.shadow_enabled = false
	beam.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	set_equipped(false)


func _unhandled_input(event: InputEvent) -> void:
	var dialogue: Node = get_tree().get_first_node_in_group("dialogue_ui")

	if dialogue != null:
		if bool(dialogue.get("is_dialogue_active")):
			return

	if event.is_action_pressed("toggle_flashlight") and not event.is_echo():
		set_equipped(not is_equipped)


func _process(_delta: float) -> void:
	if not is_equipped:
		return

	var direction: Vector2 = get_global_mouse_position() - global_position
	if direction.length_squared() < 1.0:
		return

	global_rotation = direction.angle()
	flashlight_sprite.flip_v = direction.x < 0.0


func set_equipped(value: bool) -> void:
	is_equipped = value
	visible = value
	hide_beam()


func hide_beam() -> void:
	if beam != null:
		beam.enabled = false


# Вызывается из SurfaceSpot ПОСЛЕ вычисления точки попадания.
# target_world — мировые координаты центра пятна,
# spot_diameter — диаметр пятна в мировых пикселях.
func update_beam(target_world: Vector2, spot_diameter: float) -> void:
	if beam == null or not is_equipped:
		return

	# Переводим цель в локальную систему линзы, чтобы
	# компенсировать масштаб Player и поворот фонарика.
	var local_target: Vector2 = light_origin.to_local(target_world)
	var local_length: float = local_target.length()

	if local_length < 2.0:
		hide_beam()
		return

	var world_scale_y: float = absf(
		light_origin.global_transform.get_scale().y
	)

	var local_end_width: float = (
		spot_diameter * beam_width_multiplier
	) / maxf(world_scale_y, 0.001)

	beam.rotation = local_target.angle()
	beam.scale = Vector2(
		local_length / float(BEAM_TEXTURE_WIDTH),
		local_end_width / float(BEAM_TEXTURE_HEIGHT)
	)
	beam.energy = beam_energy
	beam.color = beam_color
	beam.enabled = true


# Текстура генерируется один раз, а затем растягивается к цели.
func create_beam_texture() -> void:
	var image: Image = Image.create(
		BEAM_TEXTURE_WIDTH,
		BEAM_TEXTURE_HEIGHT,
		false,
		Image.FORMAT_RGBA8
	)

	for x in range(BEAM_TEXTURE_WIDTH):
		var t: float = (float(x) + 0.5) / float(BEAM_TEXTURE_WIDTH)

		# Свет расширяется от узкой линзы к поверхности.
		var half_width: float = lerpf(
			1.5,
			float(BEAM_TEXTURE_HEIGHT) * 0.5,
			t
		)

		# Мягко убираем резкий край в начале и конце луча.
		var start_fade: float = smoothstep(0.0, 0.035, t)
		var end_fade: float = 1.0 - smoothstep(0.82, 1.0, t)
		var distance_fade: float = lerpf(1.0, 0.45, t)

		for y in range(BEAM_TEXTURE_HEIGHT):
			var deviation: float = absf(
				float(y) + 0.5 - float(BEAM_TEXTURE_HEIGHT) * 0.5
			)
			var edge_ratio: float = deviation / maxf(half_width, 0.001)

			var soft_edge: float = 1.0 - smoothstep(0.30, 1.0, edge_ratio)
			var core: float = 1.0 - smoothstep(0.0, 0.45, edge_ratio)

			var brightness: float = clampf(
				(soft_edge * 0.72 + core * 0.28)
				* start_fade
				* end_fade
				* distance_fade,
				0.0,
				1.0
			)

			image.set_pixel(
				x,
				y,
				Color(brightness, brightness, brightness, 1.0)
			)

	beam.texture = ImageTexture.create_from_image(image)

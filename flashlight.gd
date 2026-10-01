class_name HandFlashlight
extends Node2D

@export var beam_length: float = 450.0
@export var beam_width: float = 240.0

@onready var flashlight_sprite: Sprite2D = $FlashlightSprite
@onready var light_origin: Marker2D = $LightOrigin
@onready var beam: PointLight2D = $LightOrigin/PointLight2D

var is_equipped: bool = false


func _ready() -> void:
	create_beam_texture()

	beam.color = Color(1.0, 0.94, 0.78)
	beam.energy = 0.15

	set_equipped(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_flashlight"):
		set_equipped(not is_equipped)


func _process(_delta: float) -> void:
	if not is_equipped:
		return

	var direction: Vector2 = (
		get_global_mouse_position() - global_position
	)

	if direction.length_squared() < 1.0:
		return

	global_rotation = direction.angle()

	# При наведении влево фонарик не переворачивается вверх ногами.
	var pointing_left: bool = direction.x < 0.0

	flashlight_sprite.flip_v = pointing_left


func set_equipped(value: bool) -> void:
	is_equipped = value
	visible = value

	# Световое пятно создаёт SurfaceSpot.
	beam.enabled = false


func create_beam_texture() -> void:
	const WIDTH: int = 256
	const HEIGHT: int = 128

	var image: Image = Image.create(
		WIDTH,
		HEIGHT,
		false,
		Image.FORMAT_RGBA8
	)

	image.fill(Color(0.0, 0.0, 0.0, 1.0))

	for x in range(WIDTH):
		var distance_ratio: float = float(x) / float(WIDTH - 1)

		# Конус расширяется от линзы к дальнему краю.
		var half_width: float = lerpf(
			2.0,
			float(HEIGHT) * 0.5,
			distance_ratio
		)

		var distance_fade: float = (
			1.0 - smoothstep(0.1, 1.0, distance_ratio)
		)

		for y in range(HEIGHT):
			var center_distance: float = absf(
				float(y) - float(HEIGHT - 1) * 0.5
			)

			var edge_ratio: float = center_distance / half_width

			var edge_fade: float = (
				1.0 - smoothstep(0.45, 1.0, edge_ratio)
			)

			var brightness: float = edge_fade * distance_fade

			image.set_pixel(
				x,
				y,
				Color(brightness, brightness, brightness, 1.0)
			)

	beam.texture = ImageTexture.create_from_image(image)

	# Левая граница текстуры совпадает с положением линзы.
	beam.offset = Vector2(float(WIDTH) * 0.5, 0.0)

	beam.scale = Vector2(
		beam_length / float(WIDTH),
		beam_width / float(HEIGHT)
	)

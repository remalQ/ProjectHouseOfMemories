extends Node2D

@export var surface_spot: PointLight2D

@export var light_threshold: float = 0.2
@export var reveal_time: float = 0.8
@export var afterglow_time: float = 3.0
@export var fade_time: float = 2.0

@onready var inscription: Label = $Label
@onready var reveal_point: Marker2D = $RevealPoint

var visibility_amount: float = 0.0
var afterglow_left: float = 0.0

var discovered: bool = false


func _ready() -> void:
	# Обновляем надпись после обычных скриптов,
	# включая SurfaceSpot с приоритетом по умолчанию.
	process_priority = 10

	var glow_material: CanvasItemMaterial = CanvasItemMaterial.new()
	glow_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	inscription.material = glow_material

	inscription.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inscription.modulate = Color(0.55, 1.0, 0.75, 0.0)

	if surface_spot == null:
		push_warning("HiddenInscription: назначь Surface Spot.")
		set_process(false)
		return

	if not surface_spot.has_method("get_light_strength_at"):
		push_warning(
			"HiddenInscription: добавь get_light_strength_at() "
			+ "в surface_spot.gd."
		)
		set_process(false)


func _process(delta: float) -> void:
	if not is_instance_valid(surface_spot):
		return

	var light_strength: float = float(
		surface_spot.call(
			"get_light_strength_at",
			reveal_point.global_position
		)
	)

	if light_strength >= light_threshold:
		visibility_amount = move_toward(
			visibility_amount,
			1.0,
			delta / maxf(reveal_time, 0.01)
		)

		afterglow_left = afterglow_time
	else:
		afterglow_left = maxf(afterglow_left - delta, 0.0)

		if afterglow_left <= 0.0:
			visibility_amount = move_toward(
				visibility_amount,
				0.0,
				delta / maxf(fade_time, 0.01)
			)

	inscription.modulate.a = visibility_amount

	if not discovered and visibility_amount >= 0.95:
		discovered = true
		print("Обнаружена надпись: СВЕТ ПОМНИТ")


extends Node2D

signal inscription_discovered(id: String)

@export var surface_spot: PointLight2D

@export var inscription_id: String = "bedroom_inscription"
@export var permanent_after_discovery: bool = true

# Может ли надпись обнаруживаться с начала игры.
@export var unlocked_from_start: bool = true

@export var light_threshold: float = 0.2
@export var reveal_time: float = 0.8
@export var afterglow_time: float = 3.0
@export var fade_time: float = 2.0

@onready var inscription: Label = $Label
@onready var reveal_point: Marker2D = $RevealPoint

var visibility_amount: float = 0.0
var afterglow_left: float = 0.0

var discovered: bool = false
var is_unlocked: bool = true


func _ready() -> void:
	process_priority = 10

	is_unlocked = unlocked_from_start

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
		return


func _process(delta: float) -> void:
	# Заблокированная надпись полностью невидима
	# и не реагирует на фонарик.
	if not is_unlocked:
		visibility_amount = 0.0
		afterglow_left = 0.0
		inscription.modulate.a = 0.0
		return

	# После обнаружения надпись остаётся видимой.
	if discovered and permanent_after_discovery:
		visibility_amount = 1.0
		inscription.modulate.a = 1.0
		return

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

		print("Обнаружена скрытая надпись: ", inscription_id)

		inscription_discovered.emit(inscription_id)

		if permanent_after_discovery:
			visibility_amount = 1.0
			inscription.modulate.a = 1.0


# Разрешает обнаружение надписи фонариком.
func unlock() -> void:
	is_unlocked = true


# Запрещает обнаружение надписи.
func lock() -> void:
	is_unlocked = false
	visibility_amount = 0.0
	afterglow_left = 0.0

	if is_instance_valid(inscription):
		inscription.modulate.a = 0.0


# Позволяет другим системам проверить состояние надписи.
func is_discovered() -> bool:
	return discovered

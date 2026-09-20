extends Area2D


@export var starts_on: bool = false

@onready var interaction_point: Marker2D = $InteractionPoint
@onready var lamp_light: PointLight2D = $PointLight2D
@onready var glow_sprite: Sprite2D = $GlowSprite

var is_on: bool = false


func _ready() -> void:
	is_on = starts_on
	update_light()


func _input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if not event is InputEventMouseButton:
		return

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not mouse_event.pressed:
		return

	var player_node: Node = get_tree().get_first_node_in_group("player")

	if player_node == null:
		print("ОШИБКА: Player не найден")
		return

	if not player_node.has_method("move_to_interactable"):
		print("ОШИБКА: у Player нет move_to_interactable()")
		return

	player_node.call(
		"move_to_interactable",
		interaction_point.global_position,
		self
	)


func interact() -> void:
	is_on = not is_on

	update_light()


func update_light() -> void:
	lamp_light.enabled = is_on
	glow_sprite.visible = is_on

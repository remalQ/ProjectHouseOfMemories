
extends Area2D

@export var item_id: String = "bedroom_key"

@onready var interaction_point: Marker2D = $InteractionPoint

var collected: bool = false


func _input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if collected:
		return

	if not event is InputEventMouseButton:
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not event.pressed:
		return

	var player_node: Node = (
		get_tree().get_first_node_in_group("player")
	)

	if not player_node is CharacterBody2D:
		return

	var player: CharacterBody2D = player_node as CharacterBody2D

	player.move_to_interactable(
		interaction_point.global_position,
		self
	)


func interact() -> void:
	if collected:
		return

	var inventory_node: Node = (
		get_tree().get_first_node_in_group("inventory")
	)

	if inventory_node == null:
		push_warning("BedroomKey: инвентарь не найден.")
		return

	if not inventory_node.has_method("add_item"):
		push_warning("BedroomKey: отсутствует метод add_item().")
		return

	var added: bool = bool(
		inventory_node.call("add_item", item_id)
	)

	if not added:
		print("BedroomKey: не удалось добавить предмет.")
		return

	collected = true

	print("Предмет подобран: ", item_id)

	# Удаляем объект только после успешного
	# добавления предмета в инвентарь.
	queue_free()

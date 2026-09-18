extends Area2D

@onready var interaction_point: Marker2D = $InteractionPoint


func _input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var player_node: Node = get_tree().get_first_node_in_group("player")

			if player_node == null:
				print("ОШИБКА: Player не найден")
				return

			if not player_node is CharacterBody2D:
				print("ОШИБКА: player не CharacterBody2D")
				return

			var player: CharacterBody2D = player_node as CharacterBody2D

			player.move_to_interactable(
				interaction_point.global_position,
				self
			)


func interact() -> void:
	print("Игрок подошёл к столу!")

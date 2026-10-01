extends Area2D

@onready var interaction_point: Marker2D = $InteractionPoint
@onready var lamp_light: PointLight2D = $PointLight2D
@onready var glow_sprite: Sprite2D = $GlowSprite

var is_on: bool = false


func _ready() -> void:
	update_light()


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
				print("ОШИБКА: узел player не CharacterBody2D: ", player_node)
				return

			var player: CharacterBody2D = player_node as CharacterBody2D

			player.move_to_interactable(
				interaction_point.global_position,
				self
			)


func interact() -> void:
	is_on = not is_on
	update_light()


func update_light() -> void:
	lamp_light.enabled = is_on
	glow_sprite.visible = is_on

extends Area2D


@onready var interaction_point: Marker2D = $InteractionPoint

@onready var occluder_front: LightOccluder2D = $OccluderFront
@onready var occluder_back: LightOccluder2D = $OccluderBack


@export var lamp_reference: Area2D

var light_reference: PointLight2D


func _ready() -> void:
	if lamp_reference != null:
		light_reference = lamp_reference.get_node("PointLight2D") as PointLight2D

	update_occluder()


func _process(_delta: float) -> void:
	update_occluder()



func update_occluder() -> void:
	if light_reference == null:
		return

	if lamp_reference == null:
		return

	var light_depth_point: Marker2D = (
		lamp_reference.get_node_or_null("LightDepthPoint") as Marker2D
	)

	if light_depth_point == null:
		push_warning("Desk: у торшера не найден LightDepthPoint.")
		return

	# Глубина определяется основанием торшера,
	# а не высотой источника света.
	var lamp_depth: float = light_depth_point.global_position.y
	var desk_depth: float = global_position.y

	var light_is_in_front: bool = lamp_depth > desk_depth

	if light_is_in_front:
		occluder_front.show()
		occluder_back.hide()
	else:
		occluder_front.hide()
		occluder_back.show()



func _input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:

			var player_node: Node = get_tree().get_first_node_in_group("player")

			if player_node == null:
				return

			if not player_node is CharacterBody2D:
				return

			var player: CharacterBody2D = player_node as CharacterBody2D

			player.move_to_interactable(
				interaction_point.global_position,
				self
			)


func interact() -> void:
	print("Игрок подошёл к столу!")

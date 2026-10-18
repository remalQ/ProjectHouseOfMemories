
extends Area2D

@export var lamp_reference: Area2D

# Четыре визуальных состояния стола.
@export var texture_closed: Texture2D
@export var texture_top_open: Texture2D
@export var texture_middle_open: Texture2D
@export var texture_bottom_open: Texture2D

@onready var interaction_point: Marker2D = $InteractionPoint
@onready var desk_sprite: Sprite2D = $Sprite2D

@onready var occluder_front: LightOccluder2D = $OccluderFront
@onready var occluder_back: LightOccluder2D = $OccluderBack

@onready var top_drawer: Area2D = $DrawersInteraction/TopDrawer
@onready var middle_drawer: Area2D = $DrawersInteraction/MiddleDrawer
@onready var bottom_drawer: Area2D = $DrawersInteraction/BottomDrawer

var light_reference: PointLight2D

# -1 = все ящики закрыты.
# 0 = верхний, 1 = средний, 2 = нижний.
var opened_drawer: int = -1


func _ready() -> void:
	if lamp_reference != null:
		light_reference = (
			lamp_reference.get_node_or_null("PointLight2D") as PointLight2D
		)

	update_occluder()

	# Подключаем обработку нажатий на каждый ящик.
	top_drawer.input_event.connect(
		_on_drawer_input_event.bind(0)
	)

	middle_drawer.input_event.connect(
		_on_drawer_input_event.bind(1)
	)

	bottom_drawer.input_event.connect(
		_on_drawer_input_event.bind(2)
	)

	update_desk_texture()


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
		return

	var lamp_depth: float = light_depth_point.global_position.y
	var desk_depth: float = global_position.y

	var light_is_in_front: bool = lamp_depth > desk_depth

	if light_is_in_front:
		occluder_front.show()
		occluder_back.hide()
	else:
		occluder_front.hide()
		occluder_back.show()


# Обрабатывает клик по конкретному ящику.
func _on_drawer_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int,
	drawer_index: int
) -> void:
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

	# Используем существующую проверку расстояния.
	if not player.can_interact_at(interaction_point.global_position):
		return

	toggle_drawer(drawer_index)


# Открывает или закрывает выбранный ящик.
func toggle_drawer(drawer_index: int) -> void:
	if drawer_index < 0 or drawer_index > 2:
		return

	if opened_drawer == drawer_index:
		opened_drawer = -1
		print("Ящик закрыт: ", drawer_index + 1)
	else:
		opened_drawer = drawer_index
		print("Ящик открыт: ", drawer_index + 1)

	update_desk_texture()


# Обновляет спрайт в зависимости от состояния.
func update_desk_texture() -> void:
	var next_texture: Texture2D

	match opened_drawer:
		0:
			next_texture = texture_top_open
		1:
			next_texture = texture_middle_open
		2:
			next_texture = texture_bottom_open
		_:
			next_texture = texture_closed

	if next_texture != null:
		desk_sprite.texture = next_texture
	else:
		push_warning("Desk: не назначена текстура состояния ящика.")


# Сохраняем прежнюю возможность взаимодействия со столом.
func _input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
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
	print("Игрок подошёл к столу!")

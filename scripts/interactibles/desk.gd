extends Interactable

@export var lamp_reference: Area2D

# Четыре визуальных состояния стола.
@export var texture_closed: Texture2D
@export var texture_top_open: Texture2D
@export var texture_middle_open: Texture2D
@export var texture_bottom_open: Texture2D

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


# Выбирает задний или передний окклюдер: торшер может стоять
# как за столом, так и перед ним.
func update_occluder() -> void:
	if lamp_reference == null or light_reference == null:
		return

	var light_depth_point: Marker2D = (
		lamp_reference.get_node_or_null("LightDepthPoint") as Marker2D
	)

	if light_depth_point == null:
		return

	var light_is_in_front: bool = (
		light_depth_point.global_position.y > global_position.y
	)

	occluder_front.visible = light_is_in_front
	occluder_back.visible = not light_is_in_front


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

	var player: Player = Game.find_player()

	if player == null:
		return

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


func interact() -> void:
	print("Игрок подошёл к столу!")

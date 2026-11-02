extends Interactable

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

# -1 = все ящики закрыты.
# 0 = верхний, 1 = средний, 2 = нижний.
var opened_drawer: int = -1

var _sources: Array[ArtificialLightSource] = []


func _ready() -> void:
	# Источники регистрируются в группе в _enter_tree — подключаемся
	# отложенно, чтобы все источники комнаты уже были в дереве.
	call_deferred("_connect_sources")

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


## Подключается к источникам комнаты: окклюдеры обновляются
## событийно (при вкл/выкл), без покадрового опроса.
func _connect_sources() -> void:
	_sources.clear()

	for node in get_tree().get_nodes_in_group("artificial_light_sources"):
		var source := node as ArtificialLightSource

		if source == null:
			continue

		_sources.append(source)
		source.state_changed.connect(_on_source_state_changed)

	update_occluders()


func _on_source_state_changed(
	_source: ArtificialLightSource, _is_on: bool
) -> void:
	update_occluders()


## Учитывает только ВКЛЮЧЁННЫЕ источники: выключенный торшер
## не отбрасывает тень на стол.
##
## Ограничение Godot 4.7: окклюдеры нельзя раздать источникам по маскам
## (любой shadow_item_cull_mask != 1 ломает тени), поэтому при источниках
## с разных сторон используется передний окклюдер с предупреждением.
func update_occluders() -> void:
	var front_needed: bool = false
	var back_needed: bool = false

	for source in _sources:
		if not is_instance_valid(source) or not source.is_on:
			continue

		if _source_is_in_front(source):
			front_needed = true
		else:
			back_needed = true

	if front_needed and back_needed:
		push_warning(
			"Desk: источники с разных сторон стола — используется передний окклюдер."
		)
		back_needed = false

	if not front_needed and not back_needed:
		# Ни один источник не включен — тени всё равно не видно,
		# оставляем текущее состояние.
		return

	occluder_front.visible = front_needed
	occluder_back.visible = back_needed


## Определяет сторону источника по условной глубине (LightDepthPoint
## владельца, либо позиция самого источника).
func _source_is_in_front(source: ArtificialLightSource) -> bool:
	var owner_node := source.get_parent() as Node2D
	var depth_point: Node2D = null

	if owner_node != null:
		depth_point = owner_node.get_node_or_null("LightDepthPoint") as Node2D

	var reference: Node2D = depth_point if depth_point != null else source

	return reference.global_position.y > global_position.y


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

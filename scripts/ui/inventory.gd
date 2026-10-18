extends CanvasLayer

signal item_selected(item_id: String)

const SLOT_COUNT: int = 6

@export var debug_enabled: bool = true

@export var key_icon: Texture2D
@export var flashlight_icon: Texture2D

@onready var inventory_bar: Control = $InventoryBar
@onready var slots_container: HBoxContainer = $InventoryBar/Slots

@export var player_reference: CharacterBody2D
@export_range(0.1, 1.0, 0.05) var inventory_scale: float = 0.45
@export var head_gap: float = 8.0

var inventory_anchor: Marker2D

var item_ids: Array[String] = []
var slot_buttons: Array[Button] = []
var selected_item_id: String = ""

var empty_style: StyleBoxFlat
var hover_style: StyleBoxFlat
var selected_style: StyleBoxFlat


func _ready() -> void:
	add_to_group("inventory")

	create_styles()
	create_slots()
	refresh_slots()

	# Убираем прежнюю привязку к нижнему краю экрана.
	inventory_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	inventory_bar.pivot_offset = Vector2.ZERO
	inventory_bar.size = Vector2(960, 320)
	inventory_bar.scale = Vector2.ONE * inventory_scale

	if player_reference == null:
		push_warning("Inventory: назначь Player Reference.")
		inventory_bar.hide()
		set_process(false)
		set_process_input(false)
		return

	inventory_anchor = player_reference.get_node_or_null(
		"InventoryAnchor"
	) as Marker2D

	if inventory_anchor == null:
		push_warning("Inventory: внутри Player нет InventoryAnchor.")
		inventory_bar.hide()
		set_process(false)
		set_process_input(false)
		return

	update_inventory_position()



func _input(event: InputEvent) -> void:
	var dialogue: Node = get_tree().get_first_node_in_group("dialogue_ui")

	if dialogue != null:
		if bool(dialogue.get("is_dialogue_active")):
			return
	if event.is_echo():
		return

	if event.is_action_pressed("toggle_inventory"):
		inventory_bar.visible = not inventory_bar.visible
		get_viewport().set_input_as_handled()
		return

	if not debug_enabled:
		return


func create_styles() -> void:
	empty_style = make_style(Color(0.0, 0.0, 0.0, 0.0))
	hover_style = make_style(Color(0.85, 0.9, 0.85, 0.1))
	selected_style = make_style(Color(0.7, 0.85, 0.75, 0.2))

	selected_style.border_color = Color(0.7, 0.85, 0.75, 0.7)
	selected_style.set_border_width_all(1)


func make_style(background_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()

	style.bg_color = background_color
	style.set_corner_radius_all(8)

	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0

	return style


func create_slots() -> void:
	for index in range(SLOT_COUNT):
		var button: Button = Button.new()

		button.name = "Slot" + str(index + 1)
		button.text = ""
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP

		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL

		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER

		button.add_theme_stylebox_override("normal", empty_style)
		button.add_theme_stylebox_override("hover", hover_style)
		button.add_theme_stylebox_override("pressed", selected_style)
		button.add_theme_stylebox_override("focus", empty_style)

		button.pressed.connect(_on_slot_pressed.bind(index))

		slots_container.add_child(button)
		slot_buttons.append(button)


func _on_slot_pressed(index: int) -> void:
	var clicked_id: String = ""

	if index < item_ids.size():
		clicked_id = item_ids[index]

	# Повторный клик снимает выбор.
	if selected_item_id == clicked_id:
		selected_item_id = ""
	else:
		selected_item_id = clicked_id

	refresh_slots()
	item_selected.emit(selected_item_id)


func has_item(item_id: String) -> bool:
	return item_ids.has(item_id)


func add_item(item_id: String) -> bool:
	if has_item(item_id):
		return false

	if item_ids.size() >= SLOT_COUNT:
		print("Инвентарь заполнен.")
		return false

	if get_item_icon(item_id) == null:
		push_warning("Не назначена иконка предмета: " + item_id)
		return false

	item_ids.append(item_id)
	refresh_slots()

	return true


func remove_item(item_id: String) -> bool:
	if not has_item(item_id):
		return false

	item_ids.erase(item_id)

	if selected_item_id == item_id:
		selected_item_id = ""
		item_selected.emit("")

	refresh_slots()

	return true


func get_selected_item() -> String:
	return selected_item_id


func get_item_icon(item_id: String) -> Texture2D:
	match item_id:
		"bedroom_key":
			return key_icon
		"flashlight":
			return flashlight_icon
		_:
			return null


func refresh_slots() -> void:
	for index in range(slot_buttons.size()):
		var button: Button = slot_buttons[index]
		var item_id: String = ""

		if index < item_ids.size():
			item_id = item_ids[index]

		button.icon = get_item_icon(item_id)
		button.tooltip_text = ""

		if item_id != "" and item_id == selected_item_id:
			button.add_theme_stylebox_override(
				"normal",
				selected_style
			)
		else:
			button.add_theme_stylebox_override(
				"normal",
				empty_style
			)


func _process(_delta: float) -> void:
	if not is_instance_valid(inventory_anchor):
		return

	update_inventory_position()


func update_inventory_position() -> void:
	# Получаем положение маркера в координатах окна игры.
	var viewport_position: Vector2 = (
		inventory_anchor.get_global_transform_with_canvas().origin
	)

	# Переводим его в координаты CanvasLayer инвентаря.
	var anchor_position: Vector2 = (
		get_final_transform().affine_inverse() * viewport_position
	)

	var displayed_size: Vector2 = (
		inventory_bar.size * inventory_bar.scale
	)

	inventory_bar.position = anchor_position + Vector2(
		-displayed_size.x * 0.5,
		-displayed_size.y - head_gap
	)

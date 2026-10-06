extends CanvasLayer

@export var debug_enabled: bool = true

@onready var panel: PanelContainer = $Panel
@onready var item_list: ItemList = $Panel/VBox/Items
@onready var status_label: Label = $Panel/VBox/Status

# В логике используем постоянные ID.
# Названия для игрока можно менять независимо от них.
const ITEM_NAMES: Dictionary = {
	"bedroom_key": "Ключ от спальни"
}

var item_ids: Array[String] = []


func _ready() -> void:
	add_to_group("inventory")

	panel.hide()
	refresh_list()


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return

	if event.is_action_pressed("toggle_inventory"):
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()
		return

	if not debug_enabled:
		return

	if event.is_action_pressed("debug_add_key"):
		panel.show()

		if add_item("bedroom_key"):
			status_label.text = "Добавлен ключ от спальни."
		else:
			status_label.text = "Этот ключ уже есть."

		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("debug_remove_item"):
		if panel.visible:
			remove_selected_item()

		get_viewport().set_input_as_handled()


func has_item(item_id: String) -> bool:
	return item_ids.has(item_id)


func add_item(item_id: String) -> bool:
	if not ITEM_NAMES.has(item_id):
		push_warning("Неизвестный предмет: " + item_id)
		return false

	if has_item(item_id):
		return false

	item_ids.append(item_id)
	refresh_list()

	return true


func remove_item(item_id: String) -> bool:
	if not has_item(item_id):
		return false

	item_ids.erase(item_id)
	refresh_list()

	return true


func remove_selected_item() -> void:
	var selected: PackedInt32Array = item_list.get_selected_items()

	if selected.is_empty():
		status_label.text = "Сначала выбери предмет мышью."
		return

	var item_id: String = item_ids[selected[0]]
	var item_name: String = str(ITEM_NAMES[item_id])

	if remove_item(item_id):
		status_label.text = "Удалён предмет: " + item_name


func refresh_list() -> void:
	item_list.clear()

	for item_id in item_ids:
		item_list.add_item(str(ITEM_NAMES[item_id]))

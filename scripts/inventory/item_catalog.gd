extends Node


# Каталог предметов: autoload, загружающий все ItemDefinition
# из resources/items при запуске игры.
#
# Инвентарь и сцены предметов получают описания по id отсюда,
# поэтому добавление нового предмета не требует правок кода —
# достаточно создать .tres в resources/items.


const ITEMS_DIR: String = "res://resources/items"

var _items: Dictionary = {}


func _ready() -> void:
	_load_items()


func _load_items() -> void:
	_items.clear()

	var dir := DirAccess.open(ITEMS_DIR)

	if dir == null:
		push_warning(
			"ItemCatalog: каталог не найден: " + ITEMS_DIR
		)
		return

	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue

		var path: String = ITEMS_DIR + "/" + file_name
		var definition: Resource = ResourceLoader.load(
			path, "ItemDefinition"
		) as ItemDefinition

		if definition == null:
			continue

		if definition.id.is_empty():
			push_warning(
				"ItemCatalog: у ресурса нет id: " + path
			)
			continue

		_items[definition.id] = definition

	print("ItemCatalog: загружено предметов: ", _items.size())


func get_item(item_id: String) -> ItemDefinition:
	return _items.get(item_id) as ItemDefinition


func get_item_icon(item_id: String) -> Texture2D:
	var definition: ItemDefinition = get_item(item_id)

	if definition == null:
		return null

	return definition.inventory_icon


func has_item(item_id: String) -> bool:
	return _items.has(item_id)

class_name PickupItem
extends Interactable


# Универсальный подбираемый предмет. Описание (id, название,
# текстуры) берётся из ItemDefinition (.tres), поэтому для
# каждого нового предмета не нужен отдельный скрипт — только
# экземпляр этой сцены (или её наследника) со своим ресурсом.
#
# Состояние конкретного экземпляра (collected, instance_id)
# хранится здесь, а не в ItemDefinition.


signal item_collected(item_id: String, instance_id: String)

@export var item_definition: ItemDefinition

# Идентификатор конкретного объекта на карте — для будущей
# системы сохранения состояния мира.
@export var instance_id: String = ""

var collected: bool = false


# Предмет исчезает после подбора — клики больше не принимаются.
func _is_clickable() -> bool:
	return not collected and item_definition != null


func interact() -> void:
	if collected or item_definition == null:
		return

	var inventory: Inventory = Game.find_inventory()

	if inventory == null:
		push_warning("PickupItem: инвентарь не найден.")
		return

	var item_id: String = item_definition.id

	if not inventory.add_item(item_id):
		print("PickupItem: не удалось добавить предмет: ", item_id)
		return

	collected = true

	print("Предмет подобран: ", item_id)

	item_collected.emit(item_id, instance_id)

	# Удаляем объект только после успешного
	# добавления предмета в инвентарь.
	queue_free()

extends Interactable

@export var item_id: String = "bedroom_key"

var collected: bool = false


# Предмет исчезает после подбора — клики больше не принимаются.
func _is_clickable() -> bool:
	return not collected


func interact() -> void:
	if collected:
		return

	var inventory: Inventory = Game.find_inventory()

	if inventory == null:
		push_warning("BedroomKey: инвентарь не найден.")
		return

	var added: bool = inventory.add_item(item_id)

	if not added:
		print("BedroomKey: не удалось добавить предмет.")
		return

	collected = true

	print("Предмет подобран: ", item_id)

	# Удаляем объект только после успешного
	# добавления предмета в инвентарь.
	queue_free()

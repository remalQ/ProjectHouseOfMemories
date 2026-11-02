class_name InspectablePickup
extends Interactable


# Предмет в комнате, который при взаимодействии открывает
# режим детального осмотра вместо мгновенного подбора.
#
# Осмотр и подбор — две разные механики: сначала игрок
# изучает предмет в крупном плане, и только по нажатию «Взять»
# предмет попадает в инвентарь, а объект исчезает из комнаты.


@export var item_definition: ItemDefinition

# Идентификатор конкретного объекта на карте — для будущей
# системы сохранения состояния мира.
@export var instance_id: String = ""


func _is_clickable() -> bool:
	return (
		item_definition != null
		and item_definition.inspection_scene != null
	)


func interact() -> void:
	if item_definition == null:
		return

	if item_definition.inspection_scene == null:
		push_warning(
			"InspectablePickup: у предмета нет сцены осмотра."
		)
		return

	var manager: InspectionManager = Game.find_inspection()

	if manager == null:
		push_warning(
			"InspectablePickup: InspectionManager не найден в сцене."
		)
		return

	var context: Dictionary = item_definition.make_inspection_context(
		instance_id,
		true
	)

	var view: InspectionView = await manager.open(
		item_definition.inspection_scene, context
	)

	if view == null:
		return

	view.take_requested.connect(_on_take_requested)


# Игрок нажал «Взять» в крупном плане.
func _on_take_requested(item_id: String) -> void:
	var inventory: Inventory = Game.find_inventory()

	if inventory == null:
		push_warning("InspectablePickup: инвентарь не найден.")
		return

	if not inventory.add_item(item_id):
		return

	print("Предмет подобран через осмотр: ", item_id)

	# Сначала закрываем осмотр, затем убираем объект из мира.
	var manager: InspectionManager = Game.find_inspection()

	if manager != null:
		manager.close()

	queue_free()

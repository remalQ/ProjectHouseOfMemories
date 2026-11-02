extends Node


# Game — autoload-синглтон (подключается в project.godot).
# Единая точка доступа к объектам, найденным по группам, и к
# проверкам, блокирующим ввод игрока. Заменяет дублировавшийся
# поиск get_first_node_in_group("...") в разных скриптах.


# Игрок из группы "player" или null.
func find_player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


# Инвентарь из группы "inventory" или null.
func find_inventory() -> Inventory:
	return get_tree().get_first_node_in_group("inventory") as Inventory


# Интерфейс диалогов из группы "dialogue_ui" или null.
func find_dialogue() -> DialogueUI:
	return get_tree().get_first_node_in_group("dialogue_ui") as DialogueUI


# Активен ли диалог: во время него блокируются передвижение
# игрока, фонарик и игровые клики.
func is_dialogue_active() -> bool:
	var dialogue: DialogueUI = find_dialogue()

	if dialogue == null:
		return false

	return dialogue.is_dialogue_active


# Менеджер осмотра из группы "inspection_manager" или null.
func find_inspection() -> InspectionManager:
	return get_tree().get_first_node_in_group(
		"inspection_manager"
	) as InspectionManager


# Единая проверка доступности игрового мира: покрывает диалог,
# режим осмотра и (в будущем) паузу. Вместо ручных проверок
# отдельных флагов в каждом скрипте.
func is_world_input_locked() -> bool:
	if is_dialogue_active():
		return true

	var inspection: InspectionManager = find_inspection()

	if inspection == null:
		return false

	return inspection.is_busy()

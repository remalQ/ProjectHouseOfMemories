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

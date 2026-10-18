
extends Node

@export var dialogue_ui: DialogueUI


func _ready() -> void:
	if dialogue_ui == null:
		push_warning("DialogueTest: назначь Dialogue UI.")
		return

	# Ждём один кадр, чтобы интерфейс успел инициализироваться.
	await get_tree().process_frame

	dialogue_ui.show_dialogue([
		"Где я?..",
		"Кажется, здесь давно никого не было...",
		"Но почему мне кажется, что это место знакомо?",
		"Нужно осмотреть комнату."
	])

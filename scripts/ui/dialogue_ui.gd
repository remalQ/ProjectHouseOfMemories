
class_name DialogueUI
extends CanvasLayer

signal dialogue_started
signal dialogue_finished

@export_range(5.0, 120.0, 1.0) var characters_per_second: float = 35.0

@onready var dialogue_root: Control = $DialogueRoot
@onready var speaker_label: Label = $DialogueRoot/DialoguePanel/MarginContainer/VBoxContainer/SpeakerLabel
@onready var dialogue_text: RichTextLabel = $DialogueRoot/DialoguePanel/MarginContainer/VBoxContainer/DialogueText
@onready var continue_label: Label = $DialogueRoot/DialoguePanel/MarginContainer/VBoxContainer/ContinueLabel

var lines: Array[String] = []
var current_line_index: int = 0

var is_dialogue_active: bool = false
var is_typing: bool = false
var visible_progress: float = 0.0


func _ready() -> void:
	add_to_group("dialogue_ui")

	dialogue_root.hide()
	dialogue_text.visible_characters = 0
	continue_label.hide()

	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100


func _process(delta: float) -> void:
	if not is_dialogue_active or not is_typing:
		return

	visible_progress += characters_per_second * delta

	var total_characters: int = dialogue_text.get_total_character_count()

	dialogue_text.visible_characters = mini(
		int(visible_progress),
		total_characters
	)

	if dialogue_text.visible_characters >= total_characters:
		finish_typing()


func _input(event: InputEvent) -> void:
	if not is_dialogue_active:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			advance_dialogue()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey:
		if event.pressed and not event.is_echo():
			if event.keycode == KEY_ENTER \
			or event.keycode == KEY_KP_ENTER \
			or event.keycode == KEY_SPACE:
				advance_dialogue()
				get_viewport().set_input_as_handled()
				return

	# Пока активен диалог, блокируем остальные
	# игровые действия, обрабатываемые через события.
	get_viewport().set_input_as_handled()


# Универсальный вызов диалога.
func show_dialogue(
	new_lines: Array[String],
	speaker: String = "Мысли"
) -> void:
	if new_lines.is_empty():
		return

	lines = new_lines.duplicate()
	current_line_index = 0

	speaker_label.text = speaker

	is_dialogue_active = true
	dialogue_root.show()

	show_current_line()
	dialogue_started.emit()


func show_current_line() -> void:
	if current_line_index >= lines.size():
		finish_dialogue()
		return

	dialogue_text.text = lines[current_line_index]

	visible_progress = 0.0
	dialogue_text.visible_characters = 0

	is_typing = true
	continue_label.hide()


func finish_typing() -> void:
	is_typing = false

	dialogue_text.visible_characters = -1
	continue_label.show()


func advance_dialogue() -> void:
	if not is_dialogue_active:
		return

	# Первое нажатие завершает печать.
	if is_typing:
		finish_typing()
		return

	# Следующее нажатие переключает реплику.
	current_line_index += 1

	if current_line_index >= lines.size():
		finish_dialogue()
	else:
		show_current_line()


func finish_dialogue() -> void:
	if not is_dialogue_active:
		return

	is_dialogue_active = false
	is_typing = false

	dialogue_root.hide()
	lines.clear()

	dialogue_finished.emit()

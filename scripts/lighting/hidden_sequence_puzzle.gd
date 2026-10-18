
extends Node

signal puzzle_completed

# Список подсказок в порядке обнаружения.
@export var clues: Array[Node2D] = []
@export var key_reference: Area2D

var current_clue_index: int = 0
var completed: bool = false


func _ready() -> void:
	if key_reference != null:
		key_reference.hide()
		key_reference.set_process_input(false)
		key_reference.input_pickable = false
	if clues.is_empty():
		push_warning("HiddenSequencePuzzle: список Clues пуст.")
		return

	# Сначала блокируем все подсказки.
	for clue in clues:
		if not is_instance_valid(clue):
			push_warning("HiddenSequencePuzzle: отсутствует подсказка.")
			return

		if not clue.has_method("lock"):
			push_warning("HiddenSequencePuzzle: у подсказки нет метода lock().")
			return

		if not clue.has_method("unlock"):
			push_warning("HiddenSequencePuzzle: у подсказки нет метода unlock().")
			return

		clue.lock()

	# Подключаем сигналы обнаружения.
	for i in range(clues.size()):
		var clue: Node2D = clues[i]

		clue.inscription_discovered.connect(
			_on_clue_discovered.bind(i)
		)

	# Разрешаем обнаружение только первой подсказки.
	clues[0].unlock()

	print("Головоломка активирована. Доступна первая подсказка.")


func _on_clue_discovered(
	_id: String,
	clue_index: int
) -> void:
	if completed:
		return

	# Запрещаем нарушение последовательности.
	if clue_index != current_clue_index:
		return

	print("Найдена подсказка ", clue_index + 1, " из ", clues.size())

	current_clue_index += 1

	if current_clue_index >= clues.size():
		complete_puzzle()
		return

	# Разблокируем следующую подсказку.
	clues[current_clue_index].unlock()



func complete_puzzle() -> void:
	if completed:
		return

	completed = true

	print("Головоломка завершена!")

	# Показываем ключ после последней подсказки.
	if is_instance_valid(key_reference):
		key_reference.show()
		key_reference.input_pickable = true

		print("Ключ появился в комнате!")
	else:
		push_warning(
			"HiddenSequencePuzzle: не назначен Key Reference."
		)

	puzzle_completed.emit()

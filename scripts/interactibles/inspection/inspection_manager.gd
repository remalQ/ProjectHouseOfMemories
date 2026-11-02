class_name InspectionManager
extends Node


# Центральный управляющий узел режима осмотра.
#
# Единственный активный осмотр одновременно. Знает только про
# открытие/закрытие и стек контекстов (для будущего вложенного
# осмотра: комната → стол → записка). Содержимое подсцен ему
# неизвестно.
#
# Состояния защищают от дублирования окон при быстрых кликах:
# open() и close() работают только из корректного состояния.


signal state_changed(new_state: State)

enum State { CLOSED, OPENING, ACTIVE, CLOSING }

const MAX_DEPTH: int = 2

@export var viewer: InspectionViewer

var state: State = State.CLOSED
var stack: Array[InspectionView] = []


func _ready() -> void:
	add_to_group("inspection_manager")

	if viewer == null:
		viewer = InspectionViewer.new()
		viewer.name = "InspectionViewer"
		add_child(viewer)

	viewer.close_requested.connect(close)


func is_busy() -> bool:
	return state != State.CLOSED


# Открывает подсцену осмотра. Возвращает её экземпляр (чтобы
# вызвавший объект мог подписаться на take_requested) либо
# null, если открытие невозможно.
func open(
	inspection_scene: PackedScene,
	context: Dictionary = {}
) -> InspectionView:
	if state != State.CLOSED:
		return null

	if inspection_scene == null:
		push_warning("InspectionManager: сцена осмотра не задана.")
		return null

	if stack.size() >= MAX_DEPTH:
		push_warning("InspectionManager: превышена глубина осмотра.")
		return null

	var view: InspectionView = (
		inspection_scene.instantiate() as InspectionView
	)

	if view == null:
		push_warning(
			"InspectionManager: корень сцены не InspectionView."
		)
		return null

	state = State.OPENING
	state_changed.emit(state)

	view.setup(context)
	view.close_requested.connect(close)
	stack.append(view)

	await viewer.present(view)

	state = State.ACTIVE
	state_changed.emit(state)

	return view


# Закрывает текущий осмотр и возвращает управление комнатой.
func close() -> void:
	if state != State.ACTIVE:
		return

	state = State.CLOSING
	state_changed.emit(state)

	var view: InspectionView = stack.pop_back()

	await viewer.dismiss(view)

	state = State.CLOSED
	state_changed.emit(state)


# Esc закрывает осмотр только в активном состоянии,
# поэтому быстрое нажатие не создаёт гонок.
func _unhandled_input(event: InputEvent) -> void:
	if state != State.ACTIVE:
		return

	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()

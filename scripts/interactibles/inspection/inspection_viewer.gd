class_name InspectionViewer
extends CanvasLayer


# Визуальная оболочка режима осмотра: затемнение фона,
# центрированный контейнер для подсцены и кнопка закрытия.
#
# Не знает ничего о содержимом осмотра — работает с любым
# InspectionView. Управление вводом: полноэкранная подложка
# с MOUSE_FILTER_STOP перехватывает клики, не пропуская их
# к объектам комнаты.


signal close_requested

const DIM_ALPHA: float = 0.6
const ANIMATION_TIME: float = 0.25

var dim: ColorRect
var slot: CenterContainer
var close_button: Button


func _ready() -> void:
	layer = 30
	visible = false

	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	slot = CenterContainer.new()
	slot.name = "Slot"
	slot.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(slot)

	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "✕  Закрыть (Esc)"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.mouse_filter = Control.MOUSE_FILTER_STOP

	close_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_button.offset_left = -220.0
	close_button.offset_top = 16.0
	close_button.offset_right = -16.0
	close_button.offset_bottom = 56.0

	close_button.pressed.connect(
		func() -> void: close_requested.emit()
	)
	add_child(close_button)


# Показывает подсцену: затемнение + масштабирование от 0.85
# к 1.0. Вызывается через await из InspectionManager.
func present(view: InspectionView) -> void:
	current_view_cleanup()

	slot.add_child(view)
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = true

	dim.modulate = Color(1, 1, 1, 0)
	view.modulate = Color(1, 1, 1, 0)
	view.pivot_offset = view.size * 0.5
	view.scale = Vector2.ONE * 0.85

	var tween: Tween = create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		dim, "color:a", DIM_ALPHA, ANIMATION_TIME
	)
	tween.tween_property(
		view, "modulate:a", 1.0, ANIMATION_TIME
	)
	tween.tween_property(
		view, "scale", Vector2.ONE, ANIMATION_TIME
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	await tween.finished


# Скрывает подсцену и возвращает комнату. Вызывается через await.
func dismiss(view: InspectionView) -> void:
	if not is_instance_valid(view):
		visible = false
		return

	var tween: Tween = create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		dim, "color:a", 0.0, ANIMATION_TIME
	)
	tween.tween_property(
		view, "modulate:a", 0.0, ANIMATION_TIME
	)

	await tween.finished

	if is_instance_valid(view):
		view.queue_free()

	visible = false


# Переключение на другую подсцену (вложенный осмотр) пока
# не используется, но защищает от утечек узлов.
func current_view_cleanup() -> void:
	for child in slot.get_children():
		child.queue_free()


# Перехватываем клики поверх затемнения, чтобы случайный клик
# мимо подсцены не дошёл до мира и не закрыл осмотр.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()

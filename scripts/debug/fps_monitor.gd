extends CanvasLayer

# Отладочное отображение FPS в углу экрана.
# F3 — показать/скрыть. Показывает FPS и время кадра (мс),
# обновляется 4 раза в секунду, чтобы цифры не мельтешили.

var _fps_label: Label
var _update_accumulator: float = 0.0
var _update_interval: float = 0.25


func _ready() -> void:
	layer = 100

	_fps_label = Label.new()
	_fps_label.name = "FpsLabel"
	_fps_label.position = Vector2(12, 12)
	_fps_label.add_theme_font_size_override("font_size", 20)
	_fps_label.add_theme_color_override(
		"font_color",
		Color(1.0, 1.0, 0.6)
	)
	_fps_label.add_theme_color_override(
		"font_outline_color",
		Color(0.0, 0.0, 0.0)
	)
	_fps_label.add_theme_constant_override("outline_size", 4)
	add_child(_fps_label)

	visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
			and not event.echo and event.keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return

	_update_accumulator += delta
	if _update_accumulator < _update_interval:
		return
	_update_accumulator = 0.0

	var frame_ms: float = 1000.0 * delta
	_fps_label.text = "FPS: %d (%.1f ms)" % [
		Engine.get_frames_per_second(),
		frame_ms
	]

	# Цвет как грубый индикатор: зелёный — норма, жёлтый — проседание,
	# красный — проблема.
	if frame_ms <= 20.0:
		_fps_label.add_theme_color_override(
			"font_color",
			Color(0.6, 1.0, 0.6)
		)
	elif frame_ms <= 40.0:
		_fps_label.add_theme_color_override(
			"font_color",
			Color(1.0, 1.0, 0.6)
		)
	else:
		_fps_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.5, 0.5)
		)

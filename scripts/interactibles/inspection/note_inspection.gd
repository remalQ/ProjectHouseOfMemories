extends InspectionView


# Универсальная подсцена осмотра записки/письма/фотографии.
#
# Показывает крупное изображение, поддерживает переворот на
# обратную сторону и кнопку «Взять» (передача предмета в
# инвентарь). Для записок с уникальными взаимодействиями
# можно сделать наследника с собственной сценой.
#
# Весь интерфейс строится из кода — по образцу inventory.gd.


const ANIMATION_TIME: float = 0.2

var item_id: String = ""
var instance_id: String = ""
var display_name: String = ""
var description: String = ""
var texture: Texture2D
var can_take: bool = true

var is_flipped: bool = false

var image_rect: TextureRect
var flip_button: Button
var take_button: Label
var take_panel: PanelContainer


func setup(context: Dictionary) -> void:
	item_id = context.get("item_id", "")
	instance_id = context.get("instance_id", "")
	display_name = context.get("display_name", "")
	description = context.get("description", "")
	texture = context.get("texture")
	can_take = context.get("can_take", true)

	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	var title: Label = Label.new()
	title.text = display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	image_rect = TextureRect.new()
	image_rect.texture = texture
	image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_rect.custom_minimum_size = Vector2(640, 480)
	image_rect.pivot_offset = image_rect.custom_minimum_size * 0.5
	image_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	image_rect.gui_input.connect(_on_image_input)
	vbox.add_child(image_rect)

	if not description.is_empty():
		var caption: Label = Label.new()
		caption.text = description
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.custom_minimum_size = Vector2(640, 0)
		vbox.add_child(caption)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	vbox.add_child(buttons)

	flip_button = Button.new()
	flip_button.text = "Перевернуть"
	flip_button.focus_mode = Control.FOCUS_NONE
	flip_button.pressed.connect(flip)
	buttons.add_child(flip_button)

	take_panel = PanelContainer.new()
	take_panel.visible = can_take
	buttons.add_child(take_panel)

	take_button = Label.new()
	take_button.text = "Взять"
	take_button.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	take_panel.gui_input.connect(_on_take_input)
	take_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	take_panel.add_child(take_button)


# Переворот по клику на само изображение.
func _on_image_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		flip()


func _on_take_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		request_take(item_id)


# Показывает обратную сторону: зеркальная копия, слегка
# затемнённая. Анимация «складывания» через масштаб по X.
func flip() -> void:
	var tween: Tween = create_tween()

	tween.tween_property(
		image_rect, "scale:x", 0.0, ANIMATION_TIME
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await tween.finished

	is_flipped = not is_flipped

	image_rect.flip_h = is_flipped
	image_rect.modulate = (
		Color(0.75, 0.75, 0.8) if is_flipped else Color.WHITE
	)

	var open_tween: Tween = create_tween()

	open_tween.tween_property(
		image_rect, "scale:x", 1.0, ANIMATION_TIME
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

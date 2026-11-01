extends Label

@export var interaction_point: Marker2D
@export var fade_speed: float = 8.0
@export var hint_enabled: bool = true

var player: Player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Надпись рисуется поверх обычных объектов.
	z_as_relative = false
	z_index = 100

	# Текст остаётся читаемым в тёмной комнате.
	var text_material: CanvasItemMaterial = CanvasItemMaterial.new()
	text_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = text_material

	modulate.a = 0.0

	player = Game.find_player()

	if interaction_point == null:
		push_warning("InteractionLabel: назначь Interaction Point.")
		set_process(false)
		return

	if player == null:
		push_warning("InteractionLabel: не найден Player в группе \"player\".")
		set_process(false)


func _process(delta: float) -> void:
	var target_alpha: float = 0.0

	if hint_enabled and is_instance_valid(player):
		if player.can_interact_at(interaction_point.global_position):
			target_alpha = 1.0

	modulate.a = move_toward(
		modulate.a,
		target_alpha,
		fade_speed * delta
	)

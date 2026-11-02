class_name Interactable
extends Area2D


# Базовый класс интерактивных объектов: обработка клика по
# коллайдеру, точка взаимодействия и вызов interact() у игрока.
#
# Наследники переопределяют interact() (реакция на игрока) и при
# необходимости _is_clickable() (блокировка клика по состоянию).
# Проверка дистанции выполняется в player.try_interact() через
# can_interact_at(interaction_point.global_position).


@onready var interaction_point: Marker2D = $InteractionPoint


func _input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	_handle_click(event)


# Обрабатывает клик по коллайдеру объекта.
func _handle_click(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not event.pressed:
		return

	if not _is_clickable():
		return

	# Во время осмотра/диалога клики в мир не проходят.
	if Game.is_world_input_locked():
		return

	var player: Player = Game.find_player()

	if player == null:
		return

	player.try_interact(interaction_point.global_position, self)


# Клики разрешены по умолчанию. Переопределяется в наследниках:
# например, подобранный предмет перестаёт реагировать на клики.
func _is_clickable() -> bool:
	return true


# Реакция на взаимодействие. Вызывается игроком, только если
# объект в пределах interaction_distance игрока.
# Переопределяется в наследниках.
func interact() -> void:
	pass

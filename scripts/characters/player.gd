class_name Player
extends CharacterBody2D

@export var speed: float = 420.0
@export var interaction_distance: float = 90.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var is_moving: bool = false


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING



func _physics_process(_delta: float) -> void:
	# Блокируем передвижение во время диалога и осмотра.
	if Game.is_world_input_locked():
		velocity = Vector2.ZERO
		is_moving = false

		if sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")

		return

	# Получаем направление движения через WASD.
	var direction: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	# Перемещение персонажа.
	velocity = direction * speed
	move_and_slide()

	# Проверяем, движется ли персонаж.
	is_moving = get_real_velocity().length_squared() > 1.0

	# Разворачиваем спрайт по горизонтали.
	if absf(direction.x) > 0.05:
		sprite.flip_h = direction.x > 0.0

	# Управляем анимациями.
	if is_moving and sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")
	else:
		sprite.play("idle")



# Взаимодействие с объектом, если игрок в пределах дистанции.
func try_interact(
	interaction_position: Vector2,
	object: Interactable
) -> void:
	if Game.is_world_input_locked():
		return

	if not is_instance_valid(object):
		return

	if not can_interact_at(interaction_position):
		return

	object.interact()


func can_interact_at(interaction_position: Vector2) -> bool:
	return global_position.distance_to(
		interaction_position
	) <= interaction_distance

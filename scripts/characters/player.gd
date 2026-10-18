extends CharacterBody2D

@export var speed: float = 420.0
@export var interaction_distance: float = 90.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var is_moving: bool = false


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING



func _physics_process(_delta: float) -> void:
	# Блокируем передвижение во время диалога.
	if is_dialogue_active():
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



func try_interact(
	interaction_position: Vector2,
	object: Node
) -> void:
	if is_dialogue_active():
		return
	if not is_instance_valid(object):
		return

	if not object.has_method("interact"):
		return

	if not can_interact_at(interaction_position):
		return

	object.call("interact")


# Совместимость с существующими скриптами Desk, Lamp и Door.
# Автоматического движения здесь больше нет.
func move_to_interactable(
	interaction_position: Vector2,
	object: Node
) -> void:
	try_interact(interaction_position, object)

func can_interact_at(interaction_position: Vector2) -> bool:
	return global_position.distance_to(
		interaction_position
	) <= interaction_distance

func is_dialogue_active() -> bool:
	var dialogue: Node = get_tree().get_first_node_in_group("dialogue_ui")

	if dialogue == null:
		return false

	return bool(dialogue.get("is_dialogue_active"))
	

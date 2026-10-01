extends CharacterBody2D

@export var speed: float = 220.0

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var target_object: Node = null
var is_moving: bool = false


func _physics_process(_delta: float) -> void:
	if not is_moving:
		velocity = Vector2.ZERO
		sprite.play("idle")
		return

	if navigation_agent.is_navigation_finished():
		finish_movement()
		return

	var next_position: Vector2 = navigation_agent.get_next_path_position()

	var direction: Vector2 = global_position.direction_to(next_position)

	velocity = direction * speed

	if abs(direction.x) > 0.05:
		sprite.flip_h = ! (direction.x < 0)

	move_and_slide()


func move_to_interactable(
	interaction_position: Vector2,
	object: Node
) -> void:
	target_object = object
	is_moving = true

	navigation_agent.target_position = interaction_position


func finish_movement() -> void:
	velocity = Vector2.ZERO
	is_moving = false

	var object: Node = target_object
	target_object = null

	if is_instance_valid(object) and object.has_method("interact"):
		object.interact()

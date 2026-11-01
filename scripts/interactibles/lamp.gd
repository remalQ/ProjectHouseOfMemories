extends Interactable

@onready var lamp_light: PointLight2D = $PointLight2D
@onready var glow_sprite: Sprite2D = $GlowSprite

var is_on: bool = false


func _ready() -> void:
	update_light()


func interact() -> void:
	is_on = not is_on
	update_light()


func update_light() -> void:
	lamp_light.enabled = is_on
	glow_sprite.visible = is_on

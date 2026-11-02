extends Interactable
## Торшер: игровая оболочка над компонентом ArtificialLightSource.
## Сам источник света и его настройки живут в компоненте и LightProfile.

const HINT_ON: String = "Выключить торшер"
const HINT_OFF: String = "Включить торшер"

@onready var light_source: ArtificialLightSource = $ArtificialLightSource
@onready var interaction_label: Label = $InteractionLabel


func _ready() -> void:
	_update_hint()


func interact() -> void:
	light_source.toggle()
	_update_hint()


## Горит ли лампа (для сюжетных проверок и будущего WorldState).
func is_lit() -> bool:
	return light_source.is_on


## Обновляет подсказку под текущее состояние.
func _update_hint() -> void:
	if interaction_label == null:
		return

	if light_source.is_on:
		interaction_label.text = HINT_ON
	else:
		interaction_label.text = HINT_OFF

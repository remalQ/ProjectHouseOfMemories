extends Node2D
## Диагностика масок теней Godot 4.7: каждые 40 кадров применяет новую
## конфигурацию масок и печатает её. Смотрим записанные кадры.

var _case_index: int = -1


func _ready() -> void:
	_next_case()


func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 40 == 0:
		_next_case()


func _next_case() -> void:
	_case_index += 1
	var light := $Light as PointLight2D
	var occluder := $Blocker/Occ as LightOccluder2D

	match _case_index % 6:
		0:
			light.range_item_cull_mask = 1
			light.shadow_item_cull_mask = 1
			occluder.occluder_light_mask = 1
		1:
			light.range_item_cull_mask = 1
			light.shadow_item_cull_mask = 2
			occluder.occluder_light_mask = 2
		2:
			light.range_item_cull_mask = 2
			light.shadow_item_cull_mask = 2
			occluder.occluder_light_mask = 2
		3:
			light.range_item_cull_mask = 3
			light.shadow_item_cull_mask = 2
			occluder.occluder_light_mask = 2
		4:
			light.range_item_cull_mask = 1
			light.shadow_item_cull_mask = 1
			occluder.occluder_light_mask = 2
		5:
			light.range_item_cull_mask = 1
			light.shadow_item_cull_mask = 3
			occluder.occluder_light_mask = 2

	print(
		"кадр ", Engine.get_process_frames(),
		" | range=", light.range_item_cull_mask,
		" shadow=", light.shadow_item_cull_mask,
		" occ=", occluder.occluder_light_mask
	)

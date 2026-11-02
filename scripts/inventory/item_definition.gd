class_name ItemDefinition
extends Resource


# Описание предмета как контента: идентификатор, название,
# иконки и тексты. Хранится в .tres (resources/items).
#
# Важно: ресурс описывает ТИП предмета, а не состояние
# конкретного экземпляра в мире (подобран/не подобран).
# Один .tres может использоваться несколькими экземплярами.


@export var id: String
@export var display_name: String
@export_multiline var description: String

# Как предмет выглядит в комнате и в инвентаре.
@export var world_texture: Texture2D
@export var inventory_icon: Texture2D

# Крупный план для режима осмотра (если предмет осматривается).
@export var inspection_texture: Texture2D

# Подсцена осмотра (корень — InspectionView). Если задана,
# предмет можно осматривать и из мира, и из инвентаря.
@export var inspection_scene: PackedScene


# Единый контекст для подсцены осмотра. Используется и при
# осмотре предмета в комнате, и при открытии из инвентаря.
func make_inspection_context(
	instance_id: String = "",
	can_take: bool = true
) -> Dictionary:
	return {
		"item_id": id,
		"display_name": display_name,
		"description": description,
		"instance_id": instance_id,
		"texture": inspection_texture,
		"can_take": can_take,
	}

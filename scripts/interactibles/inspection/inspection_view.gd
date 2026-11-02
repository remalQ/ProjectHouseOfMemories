class_name InspectionView
extends Control


# Базовый класс подсцены детального осмотра.
#
# InspectionManager управляет открытием/закрытием и блокировкой
# мира, а конкретная подсцена (записка, ящик, механизм) решает,
# что показывать и на что можно нажимать внутри крупного плана.
#
# Контракт с менеджером:
# - setup(context) вызывается до добавления в viewer;
# - close_requested — подсцена просит закрыть осмотр;
# - take_requested(item_id) — подсцена просит выдать предмет
#   игроку (обычно после нажатия «Взять»).


signal close_requested
signal take_requested(item_id: String)


# Заполнение подсцены данными предмета/объекта.
# Контекст — словарь: item_id, display_name, description,
# instance_id, texture и т.п. Переопределяется в наследниках.
func setup(_context: Dictionary) -> void:
	pass


func request_close() -> void:
	close_requested.emit()


func request_take(item_id: String) -> void:
	take_requested.emit(item_id)

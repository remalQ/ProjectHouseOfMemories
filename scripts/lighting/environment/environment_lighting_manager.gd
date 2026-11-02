class_name EnvironmentLightingManager
extends Node
## Контроллер искусственного освещения одной локации.
##
## Ведёт реестр источников ArtificialLightSource комнаты и даёт массовые
## команды: по группам (электричество, декоративное, аварийное) и всем
## источникам сразу. Не рисует свет и не управляет узлами мебели —
## только маршрутизация команд (см. docs/lighting/environment_lighting_refactor.md).
##
## Не autoload: у каждой комнаты свой менеджер.

## Группы источников (синхронизированы с флагами LightProfile.groups).
enum LightGroup {
	NONE = 0,
	ELECTRIC = 1,
	DECORATIVE = 2,
	EMERGENCY = 4,
}

signal source_registered(source: ArtificialLightSource)
signal source_unregistered(source: ArtificialLightSource)

# --- Настройки ---

## Корень поддерева для автосбора источников. Пусто — собрать всех
## потомков родителя (обычно корень комнаты).
@export var sources_root: NodePath

## Автоматически собрать источники из поддерева при запуске комнаты.
@export var auto_collect: bool = true

# --- Состояние ---

var _sources: Array[ArtificialLightSource] = []


func _ready() -> void:
	if auto_collect:
		_collect_sources()


func _exit_tree() -> void:
	_sources.clear()


# --- Реестр ---

## Регистрирует источник (вызывается автоматически при автосборе или
## вручную при спавне источника во время игры).
func register_source(source: ArtificialLightSource) -> void:
	if source == null or _sources.has(source):
		return

	_sources.append(source)
	source.tree_exiting.connect(unregister_source.bind(source))
	source_registered.emit(source)


## Убирает источник из реестра.
func unregister_source(source: ArtificialLightSource) -> void:
	if not _sources.has(source):
		return

	_sources.erase(source)
	source_unregistered.emit(source)


## Все зарегистрированные источники.
func get_sources() -> Array[ArtificialLightSource]:
	return _sources.duplicate()


## Источники, у которых в профиле выставлен флаг группы.
func get_sources_in_group(group: int) -> Array[ArtificialLightSource]:
	var result: Array[ArtificialLightSource] = []

	for source in _sources:
		if source.profile != null and (source.profile.groups & group) != 0:
			result.append(source)

	return result


# --- Команды: все источники ---

func turn_on_all() -> void:
	for source in _sources:
		source.turn_on()


func turn_off_all() -> void:
	for source in _sources:
		source.turn_off()


func set_energy_factor_all(factor: float) -> void:
	for source in _sources:
		source.set_energy_factor(factor)


# --- Команды: группы ---

func turn_on_group(group: int) -> void:
	for source in get_sources_in_group(group):
		source.turn_on()


## Выключает группу источников (например, «свет вырубился»).
func turn_off_group(group: int) -> void:
	for source in get_sources_in_group(group):
		source.turn_off()


## Массовое приглушение группы (аварийный режим, сюжет).
func set_energy_factor_group(group: int, factor: float) -> void:
	for source in get_sources_in_group(group):
		source.set_energy_factor(factor)


# --- Внутренняя логика ---

## Собирает источники из поддерева корня.
func _collect_sources() -> void:
	var root := get_node_or_null(sources_root) as Node

	if root == null:
		root = get_parent()

	if root == null:
		push_warning(
			"EnvironmentLightingManager: не найден корень для сбора источников."
		)
		return

	for child in root.find_children(
		"*", "ArtificialLightSource", true, false
	):
		register_source(child as ArtificialLightSource)

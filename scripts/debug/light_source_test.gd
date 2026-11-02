extends Node2D
## Тестовая сцена Этапов 1–2: два независимых источника и менеджер освещения.
##
## Проверка:
## 1/2 — включить/выключить источники по отдельности;
## Space — включить/выключить ВСЕ источники через EnvironmentLightingManager;
## P — «отключение электричества»: группа ELECTRIC гаснет, свеча горит;
## O — включить все источники;
## Стрелки — множитель энергии через менеджер;
## F — сменить профиль второго источника (apply_profile, shared-ресурс).

@onready var manager: EnvironmentLightingManager = $LightingManager
@onready var source_a: ArtificialLightSource = $Sources/LampSource
@onready var source_b: ArtificialLightSource = $Sources/CandleSource
@onready var source_c: ArtificialLightSource = $Sources/EmergencySource

var _alt_profile: LightProfile


func _ready() -> void:
	_alt_profile = load(
		"res://resources/lighting/environment/floor_lamp_profile.tres"
	) as LightProfile

	# Источники включены при старте для наглядности.
	source_a.turn_on()
	source_b.turn_on()
	source_c.turn_on()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return

	match event.keycode:
		KEY_1:
			source_a.toggle()
		KEY_2:
			source_b.toggle()
		KEY_3:
			source_c.toggle()
		KEY_SPACE:
			_toggle_all_via_manager()
		KEY_P:
			_power_outage()
		KEY_O:
			manager.turn_on_all()
		KEY_UP:
			_shift_energy_factor(0.1)
		KEY_DOWN:
			_shift_energy_factor(-0.1)
		KEY_F:
			source_b.profile = _alt_profile
			source_b.apply_profile()


## Вкл/выкл всех через менеджер.
func _toggle_all_via_manager() -> void:
	var any_off := false

	for source in manager.get_sources():
		if not source.is_on:
			any_off = true
			break

	if any_off:
		manager.turn_on_all()
	else:
		manager.turn_off_all()


## «Свет вырубился»: электрическая группа гаснет, свеча продолжает гореть.
func _power_outage() -> void:
	manager.turn_off_group(EnvironmentLightingManager.LightGroup.ELECTRIC)
	print(
		"Отключение электричества. Осталось гореть: ",
		manager.get_sources().filter(
			func(source: ArtificialLightSource) -> bool: return source.is_on
		).map(func(source: ArtificialLightSource) -> String: return source.name)
	)


## Приглушение через менеджер, сразу для всех источников.
func _shift_energy_factor(step: float) -> void:
	var factor: float = clampf(source_a.energy_factor + step, 0.0, 1.0)
	manager.set_energy_factor_all(factor)
	print(
		"energy_factor = %.1f | A: on=%s E=%.2f | B: on=%s E=%.2f" % [
			factor,
			source_a.is_on,
			source_a.light.energy,
			source_b.is_on,
			source_b.light.energy,
		]
	)

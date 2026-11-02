class_name ArtificialLightSource
extends Node2D
## Универсальный компонент искусственного света.
##
## Владеет собственным PointLight2D (создаётся автоматически), применяет
## настройки LightProfile и управляет включением, выключением, плавными
## переходами и мерцанием. Игровые объекты (торшер, свеча, люстра) содержат
## этот компонент и зовут его публичный API, не трогая PointLight2D напрямую.
##
## Важно: источник НЕ должен реализовывать get_light_strength_at(),
## иначе duck-typing HiddenInscription случайно привяжет надписи к этому свету.

signal turned_on(source: ArtificialLightSource)
signal turned_off(source: ArtificialLightSource)
signal state_changed(source: ArtificialLightSource, is_on: bool)

# --- Настройки ---

## Профиль света. Ресурс read-only: всё рантайм-состояние здесь.
@export var profile: LightProfile

# --- Состояние ---

var is_on: bool = false

## Множитель энергии для сюжетного управления (0..1), применяется
## поверх базовой энергии профиля.
var energy_factor: float = 1.0

@onready var light: PointLight2D = _find_or_create_light()
@onready var glow_sprite: Sprite2D = _find_or_create_glow()

var _tween: Tween
var _flicker_time: float = 0.0
var _flicker_target: float = 1.0


func _enter_tree() -> void:
	# Группа для поиска источников игровыми объектами (стол, менеджер).
	add_to_group("artificial_light_sources")


func _ready() -> void:
	if profile == null:
		push_warning("ArtificialLightSource (%s): не назначен LightProfile." % name)

	apply_profile()
	set_process(false)


# --- Публичный API ---

## Включает источник с плавным переходом из профиля.
func turn_on() -> void:
	if is_on:
		return

	is_on = true
	_fade_to(_target_energy())
	_set_visuals(true)
	_update_processing()
	turned_on.emit(self)
	state_changed.emit(self, true)


## Выключает источник с плавным переходом из профиля.
func turn_off() -> void:
	if not is_on:
		return

	is_on = false
	_fade_to(0.0)
	if is_equal_approx(profile.fade_duration, 0.0):
		_set_visuals(false)
	_update_processing()
	turned_off.emit(self)
	state_changed.emit(self, false)


## Переключает источник.
func toggle() -> void:
	if is_on:
		turn_off()
	else:
		turn_on()


## Устанавливает множитель энергии (сюжетное приглушение, аварийный режим).
func set_energy_factor(factor: float) -> void:
	energy_factor = clampf(factor, 0.0, 1.0)

	if is_on:
		_fade_to(_target_energy())


## Мгновенно применяет настройки профиля (при смене профиля или в _ready).
func apply_profile() -> void:
	if profile == null:
		light.enabled = false
		return

	light.color = profile.color
	light.texture = profile.light_texture
	light.texture_scale = profile.texture_scale
	light.position = profile.light_offset
	light.shadow_enabled = profile.shadows_enabled
	light.shadow_item_cull_mask = profile.shadow_item_cull_mask
	light.shadow_color = profile.shadow_color

	# Свечение плафона.
	if glow_sprite != null:
		glow_sprite.texture = profile.emissive_texture
		glow_sprite.modulate = profile.emissive_color
		glow_sprite.scale = Vector2.ONE * profile.emissive_scale

	# Применяем профиль заново к текущему состоянию.
	var was_on: bool = is_on
	is_on = false
	if was_on:
		turn_on()
	else:
		light.energy = 0.0
		_set_visuals(false)


# --- Внутренняя логика ---

## Энергия, к которой источник должен прийти в состоянии «включен».
func _target_energy() -> float:
	if profile == null:
		return 0.0

	return profile.energy * energy_factor


## Плавный (или мгновенный) переход энергии к целевому значению.
## Анимированные режимы (мерцание/пульсация) сами управляют энергией
## каждый кадр, поэтому твин для них не нужен.
func _fade_to(target_energy: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

	var animated: bool = (
		profile != null
		and profile.behavior != LightProfile.Behavior.CONSTANT
	)

	if profile == null or is_equal_approx(profile.fade_duration, 0.0) or animated:
		light.energy = target_energy
		return

	_tween = create_tween()
	_tween.tween_property(light, "energy", target_energy, profile.fade_duration)


## Включает/выключает видимость свечения плафона.
func _set_visuals(visible_state: bool) -> void:
	if glow_sprite != null:
		glow_sprite.visible = visible_state


## Обработка каждый кадр нужна только анимированным включенным источникам.
func _update_processing() -> void:
	var animated: bool = (
		is_on
		and profile != null
		and profile.behavior != LightProfile.Behavior.CONSTANT
		and not is_equal_approx(profile.flicker_strength, 0.0)
	)

	set_process(animated)


func _process(delta: float) -> void:
	if profile == null:
		return

	if profile.behavior == LightProfile.Behavior.PULSE:
		_flicker_time += delta * profile.flicker_speed * TAU
		_flicker_target = (
			1.0
			+ profile.flicker_strength * sin(_flicker_time)
		)
	else:
		_flicker_time += delta * profile.flicker_speed

		if _flicker_time >= 1.0:
			_flicker_time = fmod(_flicker_time, 1.0)
			# Скачкообразный выбор новой цели — характерно для лампы/свечи.
			_flicker_target = randf_range(
				1.0 - profile.flicker_strength,
				1.0 + profile.flicker_strength
			)

	var factor: float = clampf(_flicker_target, 0.0, 2.0)
	light.energy = _target_energy() * factor

	# Свечение плафона повторяет анимацию света.
	if glow_sprite != null and not is_equal_approx(profile.emissive_color.a, 0.0):
		glow_sprite.modulate = Color(
			profile.emissive_color.r,
			profile.emissive_color.g,
			profile.emissive_color.b,
			profile.emissive_color.a * clampf(factor, 0.0, 1.0)
		)


## Находит уже назначенный в сцене PointLight2D или создаёт свой.
func _find_or_create_light() -> PointLight2D:
	var existing := get_node_or_null("Light") as PointLight2D

	if existing != null:
		return existing

	var created := PointLight2D.new()
	created.name = "Light"
	add_child(created)
	return created


## Находит узел свечения в сцене или создаёт свой.
func _find_or_create_glow() -> Sprite2D:
	var existing := get_node_or_null("EmissiveVisual") as Sprite2D

	if existing != null:
		return existing

	var created := Sprite2D.new()
	created.name = "EmissiveVisual"
	created.visible = false
	add_child(created)
	return created

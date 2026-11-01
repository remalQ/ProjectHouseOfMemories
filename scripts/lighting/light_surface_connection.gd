
class_name LightSurfaceConnection
extends Resource


# Описывает способ перехода света между двумя конкретными поверхностями.
# Профиль поверхности отвечает на вопрос "какая это поверхность",
# а связь — "как свет ведёт себя при переходе между этими двумя
# поверхностями". Один и тот же стол может иметь разные связи
# с полом и с задней стеной.
#
# Поверхности идентифицируются по именам узлов: это позволяет
# настраивать связи в редакторе и переиспользовать один ресурс
# в комнатах с одинаковыми именами поверхностей.


@export_group("Pair")

# Имя первого узла LightSurface (например, "Backwall").
@export var surface_a_name: String = ""

# Имя второго узла LightSurface (например, "Floor").
@export var surface_b_name: String = ""

# Связь действует в обоих направлениях. Если выключено,
# применяются только параметры направления A -> B.
@export var bidirectional: bool = true


@export_group("Transition")

# Способ проекции для этого перехода. Переопределяет профили
# обеих поверхностей. По умолчанию (SCREEN_SPACE) берётся
# совместимость профилей.
@export var projection_mode: LightSurfaceProfile.ProjectionMode = \
		LightSurfaceProfile.ProjectionMode.SCREEN_SPACE

# Множитель яркости света на поверхности-получателе относительно
# яркости основного пятна. Направление A -> B; при bidirectional
# используется и для B -> A, если не заданы обратные значения.
@export_range(0.0, 2.0, 0.05) var brightness_multiplier: float = 1.0

# Множитель размера пятна на поверхности-получателе.
@export_range(0.5, 3.0, 0.05) var size_multiplier: float = 1.0

# Обратное направление B -> A. Поле reverse_brightness_multiplier
# применяется только к переходу B -> A; значение 1.0 означает
# "использовать обычные множители в обе стороны".
@export_range(0.0, 2.0, 0.05) var reverse_brightness_multiplier: float = 1.0

@export_range(0.5, 3.0, 0.05) var reverse_size_multiplier: float = 1.0

# Отбрасывает ли получатель perspective-тени при этом переходе.
@export var casts_shadow_on_transition: bool = true


@export_group("Conditional Depth")

# Задаёт ли связь условную глубину для перспективных расчётов.
# Если выключено, глубина берётся из геометрии сцены
# (ShadowCasterRef и т.п.).
@export var override_depth: bool = false

# Условная глубина поверхности A.
@export var depth_a: float = 0.0

# Условная глубина поверхности B.
@export var depth_b: float = 0.0


# Проверяет, описывает ли эта связь пару поверхностей
# в любом порядке.
func matches_pair(surface_a: LightSurface, surface_b: LightSurface) -> bool:
	if not is_instance_valid(surface_a) or not is_instance_valid(surface_b):
		return false

	var name_a: String = String(surface_a.name)
	var name_b: String = String(surface_b.name)

	var forward: bool = name_a == surface_a_name and name_b == surface_b_name
	var backward: bool = bidirectional and \
			name_a == surface_b_name and name_b == surface_a_name

	return forward or backward


# Возвращает true, если переход в конкретном направлении разрешён.
func allows_direction(from_surface: LightSurface, to_surface: LightSurface) -> bool:
	if not matches_pair(from_surface, to_surface):
		return false

	if bidirectional:
		return true

	# Однонаправленная связь работает только A -> B.
	return String(from_surface.name) == surface_a_name


class_name LightSurfaceProfile
extends Resource


# Способ проекции светового пятна.
enum ProjectionMode {
	SCREEN_SPACE,
	PROJECTED_2_5D
}


# Группа, к которой относится поверхность.
enum LightGroup {
	ROOM,
	FURNITURE,
	SPECIAL
}


@export_group("Light Behavior")

# Может ли поверхность получать свет.
@export var receives_light: bool = true

# Может ли поверхность принимать проецируемые тени.
@export var receives_shadows: bool = false

# Участвует ли поверхность в перекрытии луча.
# Фактическая геометрия препятствия задаётся отдельно.
@export var blocks_light: bool = false


@export_group("Projection")

@export var projection_mode: ProjectionMode = ProjectionMode.SCREEN_SPACE

@export var light_group: LightGroup = LightGroup.ROOM


@export_group("Light Appearance")

# Умолчания внешнего вида. LightSurface сравнивает с ними значения
# профиля: поле применяется, только если оно отличается от умолчания.
# Так назначение профиля не сбрасывает параметры, настроенные в сцене.
const DEFAULT_SPOT_SHAPE: Vector2 = Vector2.ONE
const DEFAULT_SPOT_ROTATION_DEGREES: float = 0.0
const DEFAULT_BRIGHTNESS_MULTIPLIER: float = 1.0

# Форма светового пятна.
@export var spot_shape: Vector2 = DEFAULT_SPOT_SHAPE

# Поворот пятна.
@export var spot_rotation_degrees: float = DEFAULT_SPOT_ROTATION_DEGREES

# Множитель яркости.
@export_range(0.0, 4.0, 0.05) var brightness_multiplier: float = DEFAULT_BRIGHTNESS_MULTIPLIER

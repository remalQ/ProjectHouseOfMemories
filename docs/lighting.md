# Архитектура световой системы

Документ описывает подсистему освещения от фонарика игрока: как свет
попадает на поверхности, как строятся маски, тени и «проливы» света на
стыках, и как расширять систему без правок существующего кода.

## Классы

| Файл | Класс | Роль |
|---|---|---|
| `scripts/lighting/light_surface.gd` | `LightSurface` (Polygon2D) | Геометрия поверхности + доступ к поведению через профиль |
| `scripts/lighting/light_surface_profile.gd` | `LightSurfaceProfile` (Resource) | Шаблон поведения поверхности — данные, назначаемые в инспекторе |
| `scripts/lighting/surface_spot.gd` | `SurfaceSpot` (PointLight2D) | Оркестратор: луч → поверхность → маски, тени, проливы |
| `scripts/lighting/light_mask_builder.gd` | `LightMaskBuilder` | Единый генератор масок + кэширование двух проходов |
| `scripts/lighting/light_pass.gd` | `LightPass` (PointLight2D) | Вспомогательный источник со своей маской |
| `scripts/lighting/shadow_projector_2_5d.gd` | `ShadowProjector2_5D` | Обобщённая 2.5D-проекция полигонов препятствия на плоскость |
| `scripts/lighting/hidden_inscription.gd` | `HiddenInscription` | Потребитель света: проявляется при `get_light_strength_at()` выше порога |

## Поток света за кадр

```
мышь ──► SurfaceSpot._process()
          │
          ├─ 1. get_light_target(): 2.5D-подсветка точки попадания
          │      (если игрок «перед» столом, луч упирается в его силуэт)
          │
          ├─ 2. find_surface(): точка → LightSurface
          │      пропускает поверхности с receives_light() == false
          │
          ├─ 3. Профиль поверхности:
          │      light_group == FURNITURE → range_z_max = 1, иначе 0
          │      позиция / поворот / масштаб / энергия ← профиль поверхности
          │
          ├─ 4. Основная маска: LightMaskBuilder.update_mask()
          │      полигон поверхности + тени (лениво через Callable)
          │      пересборка только при изменении входов (кэш)
          │
          ├─ 5. Проливы по связям узлов (не по именам строк):
          │      стол(твёрдый) → стена (проекция пятна) + пол
          │      пол             → стена (с тенями)     + стол
          │      стена           → пол                  + стол
          │
          └─ 6. HiddenInscription сэмплирует get_light_strength_at()
```

## Профиль поверхности (шаблон поведения)

Ресурс `LightSurfaceProfile` назначается полю `light_profile` узла
`LightSurface`. Поля:

| Группа | Поле | Смысл |
|---|---|---|
| Light Behavior | `receives_light` | Участвует ли в поиске поверхности под лучом |
| Light Behavior | `receives_shadows` | Принимает ли 2.5D-тени от стола/торшера |
| Light Behavior | `blocks_light` | Перекрытие луча (задел на будущее) |
| Projection | `projection_mode` | SCREEN_SPACE / PROJECTED_2_5D (задел на будущее) |
| Projection | `light_group` | ROOM / FURNITURE / SPECIAL → Z-уровень света |
| Light Appearance | `spot_shape`, `spot_rotation_degrees`, `brightness_multiplier` | Вид пятна на поверхности |

### Правило приоритета профиля

**Профиль перекрывает поле поверхности, только если значение профиля
отличается от умолчания (`DEFAULT_*`).** Благодаря этому назначение
профиля не сбрасывает параметры, настроенные в сцене: например, стол
носит профиль с `light_group = FURNITURE`, но его `spot_shape(1.2, 0.5)`
и яркости из `desk.tscn` продолжают работать. Флаги без «легаси»-пары
(`receives_light` и т.д.) читаются из профиля напрямую.

### Существующие профили

- `resources/lighting/backwall_profile.tres` — стена: `receives_shadows = true`
  (единственная поверхность, принимающая 2.5D-тени)
- `resources/lighting/desk_light_profile.tres` — мебель: `light_group = FURNITURE`
  (все три поверхности стола в `desk.tscn`)

## Как добавить новую поверхность

Код трогать не нужно:

1. Нарисовать полигон `LightSurface` (скрипт `light_surface.gd`) в
   `SurfacesRoot` комнаты.
2. Создать профиль `.resources` (`LightSurfaceProfile`) с нужной группой
   и видом пятна, назначить его поверхности.
3. Если поверхность должна принимать тени — `receives_shadows = true`.
4. Если при её освещении должен «проливаться» свет на соседнюю
   поверхность — см. «Связи и проливы» ниже (пока требует строки в
   `SurfaceSpot._process`, см. «Известные упрощения»).

## Как добавить препятствие-тень

Тень строит `ShadowProjector2_5D.project_polygons()`, которому безразличен
тип объекта. Препятствие описывается дескриптором `ShadowCasterRef`
(внутренний класс `SurfaceSpot`): узел-препятствие, узел с силуэтами
`FlashlightShadowCaster` (дети — Polygon2D), точка условной глубины
(иначе корень), bias и tolerance. По образцу `desk_caster` / `lamp_caster`
добавьте поле и сборку в `SurfaceSpot._ready()`, а также бит в
`get_shadow_state()` и ветку в `build_shadow_polygons()`.

## Как добавить вспомогательный источник света

`LightPass.new()` → `add_child` → `setup(имя, цвет, z_min, z_max)` →
`init_mask(original_spot)`. Простая маска (обрезка пятна полигонами
поверхностей) — `apply_mask(surfaces, яркости)`. Маска с тенями строится
через `SurfaceSpot.update_mask_for_light(..., wall_pass = true)` — она
использует общий кэш прохода стены в `LightMaskBuilder`.

## Связи и проливы на стыках

Одно световое пятно физически пересекает линию стена/пол/стол: основная
маска ограничена одной поверхностью, а вспомогательные проходы достраивают
свет на соседних. Способы привязки прохода:

- **Копия трансформа** (пол↔стена, стол↔пол): центр, форма и размер
  совпадают с основным пятном, умножаются на energy/size-мультипликаторы.
- **Проекция** (стол→стена и обратно): точка попадания переводится между
  условными плоскостями глубины — теми же формулами, что и тени
  (`ShadowProjector2_5D`, `desk_caster.get_effective_depth()`).

## Контракты совместимости

- `SurfaceSpot.get_light_strength_at(world_point)` — скрытые надписи.
- `SurfaceSpot.update_surface_mask(surface, light_world)` — публичная
  обёртка основной маски.
- `HandFlashlight.update_beam(target_world, spot_diameter)` — вызывается
  из `SurfaceSpot` после вычисления точки попадания.
- Старые поля `LightSurface` (`spot_shape`, `spot_rotation_degrees`,
  `brightness_multiplier`) действуют, пока профиль не переопределяет их.

## Известные упрощения (кандидаты этапа 5)

1. **Привязка в `_ready()` по именам**: `Backwall`, `Floor`,
   `TopLightSurface` и т.д. ищутся строками один раз при загрузке.
   Вариант решения — ресурс уровня `LightBehaviorSet` с NodePath-связями.
2. **Проецируемые проливы** (стол→стена) — отдельные функции, а не данные.
3. **Попиксельные маски 128×128 на CPU** — пересобираются только при
   изменении входов (кэш), но остаются горячим местом при росте числа
   источников; кандидат на перенос в шейдер.
4. Текстуры масок пересоздаются через `ImageTexture.create_from_image()`
   — осознанное решение, подтверждённое работой проекта, до отдельной
   оптимизации.

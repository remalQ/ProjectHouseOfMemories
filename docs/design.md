# Механики и архитектура

Единый документ по проекту: что за игра, как работают её системы, из
чего состоит архитектура и как проект расширять. Световая подсистема
описана детально отдельно — [lighting.md](lighting.md); карта каталогов
и глобальных классов — [structure.md](structure.md).

---

## 1. Обзор

- **Жанр:** 2D point-and-click приключение (квест) с прямым
  WASD-передвижением.
- **Сеттинг:** герой просыпается запертым в спальне тёмного дома.
  Дом хранит воспоминания — часть истории написана на стенах и
  проявляется только под светом фонарика.
- **Движок:** Godot 4.7, рендер GL Compatibility, окно 1920×1080
  (`canvas_items`, аспект expand).
- **Главная сцена:** `scenes/levels/bedroom.tscn`.

---

## 2. Игровая петля спальни

```
Вступление (диалог «Мыслей»)
        │
        ▼
Осмотр комнаты: стол ▸ ящики ▸ торшер
        │
        ▼
Фонарик [F] ─► луч касается поверхностей ─► скрытые надписи
        │
        ▼
Пазл: 3 надписи строго в порядке (КЛЮЧ ▸ → ▸ ↓)
        │
        ▼
Появляется ключ (bedroom_key) ▸ подбор в инвентарь
        │
        ▼
Дверь (в планах): выбранный предмет == "bedroom_key" ▸ выход
```

---

## 3. Механики

### 3.1 Игрок (`scripts/characters/player.gd`, класс `Player`)

- `CharacterBody2D`, режим `MOTION_MODE_FLOATING`; скорость 420,
  дистанция взаимодействия 90.
- Движение через `Input.get_vector("move_left", "move_right", "move_up", "move_down")`.
- Флип спрайта по направлению движения; анимации `idle`/`walk`
  (`AnimatedSprite2D`, SpriteFrames заданы в `player.tscn`).
- Во время диалога: скорость обнуляется, анимация idle,
  взаимодействие запрещено.
- Состав сцены `player.tscn`:
  `AnimatedSprite2D` · `CollisionPolygon2D` · `FlashlightPivot`
  (спрайт фонарика, точка линзы `LightOrigin` и `PointFlashLight2D`) ·
  `InventoryAnchor` (маркер, к которому привязан инвентарь).

### 3.2 Взаимодействие

Кликабельные объекты наследуются от `Interactable`
(`scripts/interactibles/interactable.gd`, `Area2D`):

```
ЛКМ по коллайдеру Area2D
  ▸ Interactable._handle_click(): фильтр ЛКМ + проверка _is_clickable()
  ▸ Player.try_interact(interaction_point, self):
      - Game.is_dialogue_active()  → выход
      - can_interact_at(точка)     → дистанция ≤ 90
      ▸ object.interact()          → реакция наследника
```

- Наследники переопределяют `interact()` и при необходимости
  `_is_clickable()` (блокировка клика по состоянию, как у подобранного
  ключа).
- Подсказка `InteractionLabel` (`scripts/ui/interaction_label.gd`):
  надпись объекта в мире (z_index 100, не затемняется светом);
  проявляется, когда игрок в пределах дистанции её `InteractionPoint`.

### 3.3 Диалоги (`scripts/ui/dialogue_ui.gd`, класс `DialogueUI`)

- `CanvasLayer` (слой 20), панель «Мыслей» внизу экрана.
- Печатная машинка: `characters_per_second` (24 в `dialogue_ui.tscn`);
  первое нажатие ускоряет печать, следующее переключает реплику.
- Управление: ЛКМ / `Enter` / `Space`; пока диалог активен, остальная
  обработка ввода подавляется (`set_input_as_handled`).
- Публичное API: `show_dialogue(lines: Array[String],
  speaker: String = "Мысли")`; сигналы `dialogue_started` /
  `dialogue_finished`.
- Блокировка остального геймплея — только через
  `Game.is_dialogue_active()` (учитывают player, flashlight и inventory).

### 3.4 Инвентарь (`scripts/ui/inventory.gd`, класс `Inventory`)

- `CanvasLayer` (слой 10), 6 слотов-кнопок; панель «прилипает» к
  `InventoryAnchor` игрока (обновляется в `_process`), масштаб
  `inventory_scale` (0.65 в сцене), отступ над головой `head_gap`.
- Управление: `E` — показать/скрыть; ЛКМ по слоту — выбор предмета
  (повторный клик снимает выбор); сигнал `item_selected(item_id)`.
- API: `add_item` (дубликат запрещён — вернёт false), `remove_item`,
  `has_item`, `get_selected_item`.
- Иконки предметов выдаёт `get_item_icon()` (расширяется на новый
  предмет); сейчас: `bedroom_key`, `flashlight`.
- Во время диалога тумблер заблокирован.

### 3.5 Фонарик (`scripts/characters/flashlight.gd`, класс `HandFlashlight`)

- Узел на `FlashlightPivot` игрока; Light2D-конус ищется внутри
  `LightOrigin` по типу, чтобы не зависеть от имени узла.
- `F` — тумблер (не работает во время диалога).
- Прицел — мышь: пивот поворачивается к точке под курсором,
  спрайт вертикально флипается.
- Конус — аддитивный `PointLight2D` на генерируемой текстуре 384×192:
  растягивается от линзы до центра пятна на поверхности; растяжение
  задаёт `SurfaceSpot.update_beam()`. Видимый конус — косметика:
  реальный свет на геометрии создаёт SurfaceSpot (см. 3.6).

### 3.6 Световая система (кратко; подробно — [lighting.md](lighting.md))

```
мышь ▸ SurfaceSpot._process()
  ▸ точка попадания луча (2.5D: луч «прилипает» к столу)
  ▸ поиск LightSurface под точкой (поведение задаёт профиль)
  ▸ LightSurfaceResolver: пересечения пятна с поверхностями
  ▸ LightDistributionPlanner: план распределения (профили поверхностей,
    связи LightSurfaceConnection на стыках, 2.5D-проекция)
  ▸ LightPassManager: применение плана к LightPass-проходам
  ▸ LightMaskBuilder: попиксельная маска 128×128 (сканлайн-растеризация,
    кэш в разрезе получателя), тени строятся лениво через Callable
  ▸ ShadowProjector2_5D: проекция силуэтов стола/торшера
    (FlashlightShadowCaster) на принимающую тени поверхность
  ▸ HiddenInscription: сэмплирует SurfaceSpot.get_light_strength_at()
```

- Поверхности — `LightSurface` (Polygon2D) + ресурс
  `LightSurfaceProfile` (`resources/lighting/*.tres`): получает ли
  свет/тени, группа ROOM / FURNITURE / SPECIAL (определяет Z-слой
  освещения), форма пятна, яркость.
- Связи — `LightSurfaceConnection` (.tres): свет «проливается» на
  соседнюю поверхность; 8 связей в спальне; пара Backwall↔Floor
  обслуживается резервными проходами вне плана.
- Полигоны поверхностей невидимы (`hide()`) — это только геометрия
  для расчёта света.

### 3.7 Скрытые надписи (`scripts/lighting/hidden_inscription.gd`)

- Каждый кадр сэмплирует `get_light_strength_at(RevealPoint)`;
  порог `light_threshold = 0.2`, проявление 0.8 с, послесвечение 3 с,
  затухание 2 с.
- После обнаружения (`discovered`) надпись остаётся видимой навсегда
  (`permanent_after_discovery`) и испускает `inscription_discovered(id)`.
- `unlock()` / `lock()` — для пазла и сценарных блокировок.
- Первая надпись «СВЕТ ПОМНИТ» существует вне пазла и активна от старта.

### 3.8 Пазл последовательности (`scripts/lighting/hidden_sequence_puzzle.gd`)

- На старте блокирует все `clues` методом `lock()`, открывает только
  первую; при обнаружении в правильном порядке открывает следующую.
- После последней надписи: показывает `key_reference` (BedroomKey),
  делает его `input_pickable`, испускает `puzzle_completed`.
- Нарушение порядка игнорируется. В спальне: КЛЮЧ ▸ → ▸ ↓.

### 3.9 Предметы уровня

| Объект | Файлы | Механика |
|---|---|---|
| Стол | `desk.gd`, `desk.tscn` | 3 ящика (`DrawersInteraction/*.drawer` Area2D): открывается ровно один, спрайт переключается на текстуру состояния; `interact()` — реплика подхода к столу |
| Окклюдеры стола | `desk.gd` | Передний/задний окклюдер тени выбирается по глубине `LightDepthPoint` торшера относительно стола |
| Торшер | `lamp.gd`, `Lamp.tscn` | Тумблер тёплого света (`PointLight2D` + `GlowSprite`); его `LightDepthPoint` — условная глубина для 2.5D-тени и окклюдера стола |
| Ключ | `bedroom_key.gd`, `bedroom_key.tscn` | Появляется от пазла; `interact()` → `Inventory.add_item("bedroom_key")` → `queue_free()` |

### 3.10 Отладка (`scripts/debug/fps_monitor.gd`, autoload `FpsMonitor`)

- `F3` — оверлей: FPS и время кадра, обновление 4 Гц; цвет: зелёный
  до 20 мс, жёлтый до 40 мс, дальше красный.
- `Game` (см. 4.1) и этот модуль — единственные autoload-ы.

---

## 4. Архитектура

### 4.1 Autoloads (`project.godot`)

| Автозагрузка | Файл | API | Роль |
|---|---|---|---|
| `FpsMonitor` | `scripts/debug/fps_monitor.gd` | тумблер `F3` | Оверлей FPS |
| `Game` | `scripts/core/game.gd` | `find_player() → Player`, `find_inventory() → Inventory`, `find_dialogue() → DialogueUI`, `is_dialogue_active()` | Единый поиск по группам `player` / `inventory` / `dialogue_ui` — вместо дублирования `get_first_node_in_group()` в разных скриптах |

### 4.2 Глобальные классы

| Файл | Класс | Наследник |
|---|---|---|
| `scripts/characters/player.gd` | `Player` | CharacterBody2D |
| `scripts/characters/flashlight.gd` | `HandFlashlight` | Node2D |
| `scripts/interactibles/interactable.gd` | `Interactable` | Area2D |
| `scripts/ui/dialogue_ui.gd` | `DialogueUI` | CanvasLayer |
| `scripts/ui/inventory.gd` | `Inventory` | CanvasLayer |
| `scripts/lighting/*.gd` | 11 классов света (полный список и роли — [structure.md](structure.md)) | RefCounted / Node2D / Resource |

`SurfaceSpot` (`scripts/lighting/surface_spot.gd`) — ядро световой
подсистемы, глобального имени не имеет: привязан
к сцене комнаты, скрытые надписи используют его только через
проверку `get_light_strength_at()`.

### 4.3 Слои сцены спальни (`scenes/levels/bedroom.tscn`)

```
Bedroom (Node2D, script bedroom.gd — вступление)
├─ Background (Sprite2D, z -10)        картинка комнаты
├─ LightSurfaces (z 1)                 Backwall/LeftWall/Floor/Ceiling/RightWall
│                                      (LightSurface; полигоны скрыты)
├─ HiddenInscription … HiddenInscription4  скрытые надписи
├─ HiddenSequencePuzzle                пазл + ссылка на ключ
├─ FloorBoundary (StaticBody2D)        границы пола для движения
├─ World (Node2D, y_sort)              Player (z 2); Interactibles (z 1):
│                                      Desk, Lamp, BedroomKey
├─ DialogueUI (CanvasLayer, слой 20)
├─ Inventory (CanvasLayer, слой 10)
├─ Foreground
├─ CanvasModulate (0.31, 0.32, 0.40)   приглушающая темнота
└─ SurfaceSpot (PointLight2D)          источник световой подсистемы:
                                       player/surfaces/desk/lamp +
                                       8 connection-ресурсов
```

Свет дополнительно делится по Z: проходы группы ROOM освещают
фона z −1024…0, проход FURNITURE (z 1) рисуется поверх деталей
стола; выбор слоя определяется группой освещаемой поверхности.

### 4.4 Ввод (`project.godot`, InputMap)

| Действие | Клавиши | Использование |
|---|---|---|
| `move_left/right/up/down` | A / D / W / S | движение игрока |
| `toggle_flashlight` | F | `HandFlashlight.set_equipped()` |
| `toggle_inventory` | E | `Inventory._input()` |
| вне InputMap | ЛКМ | взаимодействие, ящики, диалоги |
| вне InputMap | `Enter` / `Space` | диалоги |

### 4.5 Конвенции кода

- GDScript со строгой типизацией (типы у параметров, возвращаемых
  значений и локалов); приватные члены — с префиксом `_`.
- Отступы — табуляция (стандарт всего проекта).
- Комментарии и реплики интерфейса — на русском.
- Вверху каждого файла — docblock: роль класса и поток данных.
- Доступ по группам — через autoload `Game`; прямые
  `get_node_or_null()` — только для внутренних узлов своей сцены.
- `print()` — временный стейт-лог механик (пазл, ящики, подбор);
  для ошибок подключения узлов используется `push_warning()`.

---

## 5. Как расширять (чеклисты)

### 5.1 Новый интерактивный объект

1. Сцена: root `Area2D` + скрипт `extends Interactable`; дети:
   `CollisionPolygon2D` (кликабельная область), `InteractionPoint`
   (Marker2D, точка дистанции), `Sprite2D`; при желании
   `InteractionLabel` (скрипт `scripts/ui/interaction_label.gd`,
   назначить `Interaction Point`, текст подсказки).
2. Переопределить `interact()`; при стейт-блокировках — `_is_clickable()`.
3. Добавить экземпляр в `World/Interactibles` уровня; если объект
   участвует в свете (окклюдеры, `FlashlightShadowCaster`, поверхности)
   — см. [lighting.md](lighting.md).

### 5.2 Новый предмет инвентаря

1. Добавитель вызывает `Inventory.add_item(item_id)` со строкой id.
2. Иконка: расширить `match` в `Inventory.get_item_icon()` и экспорт
   текстуры в `inventory.tscn`.

### 5.3 Новая реплика / осмотр объекта

`dialogue_ui.show_dialogue([...], "Спикер")` из любой ноды — диалог
сам блокирует движение и клики на время показа.

### 5.4 Новая комната

1. Скопировать каркас `bedroom.tscn`: `LightSurfaces` (полигоны
   комнаты с профилями), связи, `SurfaceSpot`, `World`, `FloorBoundary`.
2. Новые поверхности/связи настраиваются ресурсами без кода — см.
   «Как добавить новую поверхность» в [lighting.md](lighting.md).
3. Зарегистрировать переход (см. пункт 6.4 плана): дверь + смена сцены.

---

## 6. Известные упрощения и план

| # | Пункт | Почему так сейчас | Как исправлять |
|---|---|---|---|
| 1 | Дверь без скрипта и вне сцены | MVP главы не закрыт | `bedroom_door.tscn` ждёт скрипт `Interactable` + проверку выбранного ключа; дальше — переход |
| 2 | Фонарик доступен с самого старта по `F` | свет замкнут внутри себя, предметности нет | подбор фонарика как предмета `"flashlight"`; `F` работает только при наличии |
| 3 | Ящики стола пусты | `toggle_drawer()` меняет только текстуру | лут в ящиках + реплики при осмотре |
| 4 | Переходов и сохранений нет | комната одна | autoloads `LevelManager` и `Journal` (items/flags/visited); после этого сохранение в `user://` — дешёвый шаг |
| 5 | Звука нет | Контент и свет стоят первыми | шина Master/Music/SFX, шаги/ящики/дверь/эмбиент |
| 6 | `print()` как отладка | виден лог пазла/предметов/ключа | завести единый debug-лог или убрать к релиз-срезу |
| 7 | Маски света считаются на CPU | 128×128, сканлайны, кэш по входам — работает | кандидаты этапа 5 из [lighting.md](lighting.md): шейдер, `LightBehaviorSet`, проекции как данные |
| 8 | Нет меню и паузы | играется из редактора | title screen, Esc-пауза, настройки громкости |

---

*При изменении механики обновлять разделы 3 и 6 этого документа.*

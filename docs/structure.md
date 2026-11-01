# Структура проекта

Краткая карта каталогов и ответственности модулей. Световая подсистема
описана отдельно в [lighting.md](lighting.md).

```
ProjectHouseOfMemories/
├── assets/          # изображения: фоны, предметы, пропсы, персонажи, UI
├── docs/            # документация: lighting.md, structure.md
├── resources/       # ресурсы Godot (.tres): профили поверхностей, связи света
├── scenes/
│   ├── characters/  # player.tscn (в нём же FlashlightPivot, InventoryAnchor)
│   ├── interactibles/  # desk, Lamp, bedroom_key, bedroom_door, hidden_symbol
│   ├── levels/      # bedroom.tscn — сцена спальни и точка входа игры
│   └── ui/          # dialogue_ui, inventory
├── scripts/
│   ├── characters/  # player.gd (class_name Player), flashlight.gd
│   ├── core/        # game.gd — autoload Game (поиск объектов по группам)
│   ├── debug/       # fps_monitor.gd — autoload FpsMonitor (F3)
│   ├── interactibles/  # interactable.gd (базовый класс) + desk, lamp, key
│   ├── levels/      # bedroom.gd — сценарий уровня (вводная сцена)
│   ├── lighting/    # световая подсистема (см. docs/lighting.md)
│   └── ui/          # dialogue_ui, inventory, interaction_label
└── project.godot
```

## Глобальные объекты (autoload)

| Автозагрузка | Файл | Роль |
|---|---|---|
| `FpsMonitor` | `scripts/debug/fps_monitor.gd` | Оверлей FPS, тумблер F3 |
| `Game` | `scripts/core/game.gd` | Поиск игроков/инвентаря/диалогов по группам: `find_player()`, `find_inventory()`, `find_dialogue()`, `is_dialogue_active()` |

## Глобальные классы

| Файл | Класс | Наследник |
|---|---|---|
| `scripts/characters/player.gd` | `Player` | CharacterBody2D |
| `scripts/characters/flashlight.gd` | `HandFlashlight` | Node2D |
| `scripts/ui/dialogue_ui.gd` | `DialogueUI` | CanvasLayer |
| `scripts/ui/inventory.gd` | `Inventory` | CanvasLayer |
| `scripts/interactibles/interactable.gd` | `Interactable` | Area2D |
| `scripts/lighting/*.gd` | `LightSurface`, `LightSurfaceProfile`, `LightSurfaceConnection`, `LightSurfaceResolver`, `LightDistributionPlanner`, `LightDistributionPlan`, `LightPass`, `LightPassManager`, `LightMaskBuilder`, `LightProjection2_5D`, `ShadowProjector2_5D` | RefCounted/Node2D |

## Как устроено взаимодействие

1. Все кликабельные объекты наследуются от `Interactable`
   (скрипт `scripts/interactibles/interactable.gd`). Базовый класс
   ловит клик, находит игрока и передаёт ему `try_interact()`.
2. `Player.try_interact()` проверяет, нет ли активного диалога
   (`Game.is_dialogue_active()`), дистанцию до точки взаимодействия
   и вызывает `interact()` объекта.
3. Наследники `Interactable` переопределяют `interact()`
   (стол, торшер, ключ) и при необходимости `_is_clickable()`.
4. Диалоги блокируют движение, фонарик и инвентарь: вместо
   дублированных проверок группы `dialogue_ui` все скрипты
   спрашивают `Game.is_dialogue_active()`.

## Ввод

- `WASD` — движение; `E` — инвентарь; `F` — фонарик; `Enter/Space/ЛКМ` — диалоги; `F3` — FPS.
- Мышь: клики по предметам (за пределами дистанции взаимодействия
  сработать не может), поиск пятна фонарика.

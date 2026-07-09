# Burrow — Godot 4.7 Rebuild Design

**Date:** 2026-07-06
**Status:** Approved for slice 1
**Supersedes:** the Godot 3.x `prototype/` (BurrowingDemo)

## 1. Context & decision

The existing `prototype/` is a **Godot 3.x** project (`config_version=4`, `.stex`/`.mono`
artifacts, `scancode` input serialization). The goal is a game on **Godot 4.7**.

Rather than port, we **rebuild from scratch**. Rationale:

- The port's hard parts (TileMap → TileMapLayer, `KinematicBody2D`/`move_and_slide` →
  `CharacterBody2D`, `connect(...)` signal syntax, GDScript 2.0) require rewriting the exact
  systems that matter anyway — porting buys nothing there and drags 3.x idioms forward.
- The prototype is early (11 small scripts) and its value is the **design**, not the code.
- All art is being **regenerated in SpriteCook**, so the old PNGs are not even placeholders
  to keep.

**What we salvage:** the design only (captured in this doc, pulled from the old README and
the prototype's maze/larvae logic). Code and art are fresh.

**Language:** GDScript-only (the old Mono/C# setup was stale — all scripts were GDScript).

## 2. Vision (north star — NOT slice 1)

A top-down 2D game of spiders in a maze of randomised tunnels. Asymmetric, Bomberman-ish.
The aim is to **kill or starve** competing spider(s). Smaller creatures (larvae) wander the
tunnels and can be caught in webs and consumed to stave off hunger. Visibility is limited to
the area around the spider (fog of war). Defeat the opponent to **burrow down** to the next,
harder level. Greater spiders have a chance to **specialise** the deeper they get. Permadeath:
if defeated, you start again from scratch.

**Ultimate scope (well beyond slice 1), retained for architectural direction:**

- Multiplayer, multiplatform; slither.io-scale sessions with several spiders per map.
- Spider customization (shape, colour) and a basic creator.
- Trap semantics between players: you can't cross another spider's trap, but you *can*
  consume creatures trapped in it.
- Consuming **excess** creatures (past hunger) boosts power — commonly visibility / firepower
  range & damage / trap count; rarely (~1 in 5) the ability to break walls.
- Progression knobs: map size, creature scarcity, water temporarily flooding sections, more
  players.
- Specialisation classes offered after each successful run: lay eggs (fast scout/attacker
  spiderlings), coat tunnels in silk (slow the enemy), camouflage (temporary opacity/invis).

These are **explicitly out of slice 1** but the architecture leaves room for them (see §7).

## 3. Slice 1 — the vertical slice

The thinnest **complete, replayable** version of the whole loop, proving it's fun before
investing in enemy variety or meta systems.

**Core loop:** descend through procedural tunnel mazes; on each level, out-fight *or* out-eat a
competing enemy spider that also hungers; darkness hides everything but your sightline. Kill or
starve the enemy → burrow deeper (fresh, harder maze). Die → permadeath, restart at depth 1.

### In scope

| System | Slice-1 form |
|---|---|
| Maze | Recursive-backtracker tunnels → `TileMapLayer`, seeded per depth, navigation polygons on floor tiles |
| Fog of war (visual) | Maze black except a lit radius + sightline ahead; walls occlude sight (`PointLight2D` + `LightOccluder2D`). **No** proximity "sense" yet |
| Player | `CharacterBody2D`, free movement; fire web shot (cooldown); lay trap (max N active); **HP + Hunger** meters |
| Hunger | Rises over time; while maxed, drains HP; eating a trapped larva satiates it |
| Web shot | Projectile fired along facing; damages enemy; despawns on wall hit |
| Web trap | Placed in a tunnel; **blocks spiders from crossing** (yours or the enemy's); catches larvae; **either** spider can consume a trapped larva |
| Larvae | Wander tunnels, reverse at walls, get caught in traps; consumed → satiate hunger |
| Enemy | One data-driven `EnemyType`; FSM: patrol → seek_food → chase → flee-when-low; pathfinds via `NavigationAgent2D`; **also hungers** (can starve) and raids traps for food |
| Descent | Clear the enemy → generate fresh, harder maze (scaled enemy stats); HP + Hunger persist |
| HUD | HP bar, Hunger bar, depth counter |
| Difficulty | Scale enemy stats (HP / speed / hunger rate) by depth |

### Out of scope (designed-for as stubs / extension points)

- Proximity "sense" of adjacent creatures (non-visual detection) — deferred.
- Power-boosts from excess consumption — `excess_consumed` event is emitted but ignored.
- Enemy **types** & specialisation classes (eggs / silk / camouflage) — one `EnemyType` now.
- Multiplayer, customization, water hazards, map-size progression.
- Audio, menus, save/meta systems.

## 4. Architecture

### Scene tree

```
World (Node2D)                 ← main scene; owns descent flow, camera, HUD
├── Level (Node2D)             ← instanced per depth; freed & regenerated on descent
│   ├── Maze (TileMapLayer)    ← floor + walls; nav polygons on floor tiles; occluders on walls
│   ├── Entities (Node2D)
│   │   ├── Player (CharacterBody2D)
│   │   ├── Enemy  (CharacterBody2D)   ← built from an EnemyType resource
│   │   ├── Larvae × N (Node2D/CharacterBody2D)
│   │   └── Webs / Traps (spawned)
│   └── (navigation baked from Maze floor tiles)
├── Camera2D                   ← follows the player
└── HUD (CanvasLayer)          ← HP, Hunger, depth
```

### Autoloads

| Name | Responsibility |
|---|---|
| `EventBus` | Typed cross-system signals; decouples entities from `World`/HUD |
| `GameState` | Current depth, persisted player HP + Hunger, RNG seed, run lifecycle |

`World` orchestrates descent: on `EventBus.enemy_defeated`, free the current `Level`, generate
the next from `GameState.depth`, and re-place the player carrying HP + Hunger forward. On
`EventBus.player_died`, permadeath → reset `GameState`, restart at depth 1.

### EventBus signals (initial set)

```
signal larva_trapped(larva, trap)
signal larva_consumed(by, overflow: float)     # overflow feeds future power boosts
signal excess_consumed(by, amount: float)      # stub for slice 1
signal enemy_defeated(cause: String)           # "killed" | "starved"
signal player_damaged(amount: float)
signal player_died
signal hunger_changed(who, value: float, max: float)
signal health_changed(who, value: float, max: float)
signal depth_changed(depth: int)
```

## 5. Components (composition over inheritance)

Reusable child nodes so the player and enemy share behaviour rather than inherit a base class.

- **HealthComponent** — `max_health`, `take_damage()`, clamps, emits `died`.
- **HungerComponent** — grows over time; while at max, drains the sibling `HealthComponent`;
  `satiate(amount)` on eat; emits `excess_consumed` when a meal overflows past full.
- **WebEmitter** — spawns a web-shot projectile on a cooldown, along the owner's facing.
- **TrapPlacer** — spawns a trap, enforces max-active count, tracks ownership.
- **Hitbox / Hurtbox** (`Area2D`) — collision for web shots, traps, and contact.
- **Enemy FSM** + `NavigationAgent2D` — states patrol / seek_food / chase / flee; pathfinds
  over the maze's baked nav polygons; consults its own `HungerComponent` to decide seek_food.
- **Larva controller** — wander + reverse at walls; "caught" state when it enters a trap.
- **Vision/Fog controller** — a sightline light (radius + forward cone) that walls occlude;
  reveals only what's lit. Proximity "sense" is a later addition on top of this.

### Data-driven enemy

`EnemyType` is a custom `Resource`:

```
class_name EnemyType extends Resource
@export var display_name: String
@export var max_health: float
@export var move_speed: float
@export var hunger_rate: float
@export var sprite_frames: SpriteFrames
@export var skills: Array[StringName]   # empty in slice 1
```

Slice 1 ships **one** `EnemyType` with no active skills. "Specialised spiders as you descend"
later means authoring new resources (and honouring `skills`), not rewriting the enemy scene.

### Trap mechanics (slice 1)

- A trap blocks spider bodies from crossing (collision layer excludes larvae) but larvae can
  enter its `Area2D` and become **caught**.
- A caught larva can be consumed by **any** spider adjacent to the trap → `satiate()` the
  consumer, remove the larva, and (per README) the trap itself is spent on consumption.
- These rules already generalise to the multi-spider vision; slice 1 just has one enemy.

## 6. Data flow

1. Time passes → each `HungerComponent` rises; at max it drains its `HealthComponent`.
2. Player fires web shot (`WebEmitter`) → projectile → enemy `Hurtbox` → `HealthComponent`
   damage → possibly `enemy_defeated("killed")`.
3. Player/enemy lays a trap (`TrapPlacer`). Larva enters trap → `larva_trapped`. A spider
   consumes it → `HungerComponent.satiate()` → `larva_consumed` (+ overflow).
4. If a spider's hunger keeps it starving to 0 HP → `enemy_defeated("starved")` or
   `player_died`.
5. `enemy_defeated` → `World` frees `Level`, increments `GameState.depth`, generates the next
   maze, re-places the player with carried HP + Hunger, emits `depth_changed`.
6. `player_died` → permadeath: reset `GameState`, restart at depth 1.

## 7. Extension points (for the vision, not built now)

- **`EnemyType.skills`** + FSM skill hooks → specialisation classes (eggs, silk, camouflage).
- **`excess_consumed` / overflow** on `larva_consumed` → power-boost track (visibility,
  firepower, trap count, rare wall-break).
- **Vision/Fog controller** already isolates "what can this spider perceive" → drop in the
  proximity "sense" and per-spider vision-range trade-offs.
- **`Level` as a swappable unit** + seeded generation → map-size / scarcity / water
  progression knobs.
- **`EventBus` + `GameState`** as the seams a networking layer later authoritatively drives.

## 8. Project layout & assets

Co-located by feature, GDScript-only, snake_case filenames (Godot 4 convention).

```
res://
├── autoloads/          # event_bus.gd, game_state.gd
├── entities/
│   ├── player/         # player.tscn + player.gd
│   ├── enemy/          # enemy.tscn + enemy.gd + states/
│   ├── larva/          # larva.tscn + larva.gd
│   └── web/            # web_shot.tscn, web_trap.tscn (+ scripts)
├── components/         # health_component.gd, hunger_component.gd, web_emitter.gd, ...
├── world/
│   ├── world.tscn/gd   # root, descent orchestration
│   ├── level.tscn/gd   # per-depth container
│   ├── maze/           # maze generator + tile_types.gd
│   └── fog/            # vision/fog controller
├── resources/
│   └── enemies/        # EnemyType resources
├── ui/                 # hud.tscn/gd
├── assets/             # SpriteCook-generated sprites & tileset (old PNGs discarded)
├── tests/              # GUT tests
└── addons/
```

**Assets:** regenerated in **SpriteCook** → imported as `SpriteFrames` (animated entities) and
a `TileSet` (maze). The Godot 3.x `prototype/` stays untouched as reference until slice 1 is
running, then is removed.

**Project hygiene:** proper `.gitignore` (`.godot/`, exports, no `.import/`), `.gitattributes`
(LF + binary rules), input map redefined in 4.7 (WASD + arrows, fire, place-trap).

## 9. Testing

TDD on the **pure logic**; manual `/run` for feel.

- **Maze generator** — every open cell reachable (connectivity); same seed → identical maze
  (determinism).
- **HealthComponent** — damage, clamping, death signal.
- **HungerComponent** — growth, HP drain at max, satiate, overflow emission.
- **Tile-type classification** — the corner/T/crossroad detection (salvaged concept from the
  old `Maze.gd`).
- **Trap catch/consume resolution** — larva vs. spider, ownership, spend-on-consume.

Scene-level behaviour (movement feel, fog, enemy AI, descent) is verified by running the game,
not unit tests.

## 10. Open tuning parameters (decided at implementation/playtest, not here)

Hunger growth rate, starvation HP-drain rate, satiation per larva, web-shot cooldown & range,
max active traps, larva spawn cadence & cap, sight radius/cone, per-depth stat scaling curve.
These are values to feel out, not architecture.

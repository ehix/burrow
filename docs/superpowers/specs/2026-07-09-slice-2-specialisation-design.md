# Slice 2 — Specialisation, Hazards & Economy: Architectural Blueprint

Date: 2026-07-09
Status: Architecture scaffolded (schemas/components/enums land now); gameplay
wiring is a follow-up implementation plan, not this doc.
Supersedes: fleshes out the "Vision" and §7 "Extension points" of
`2026-07-06-burrow-rebuild-design.md` — specialisation classes, eggs/silk/
camouflage, water hazards, excess-consumption power-ups, and wall-break were
all named there as explicitly out of slice 1.

## 0. Scope of this pass

This is a **blueprint + structural code** pass, not a full feature build. Every
new class below compiles, is unit-tested where it's pure logic, and the whole
suite (181 tests) plus a headless boot of `world.tscn` are clean. What it
deliberately does **not** do is rewire the live gameplay loop:

- `Enemy`, `Player`, `Larva` keep their slice-1 behaviour untouched.
- New skills/items reference real current APIs (`WebTrap.try_consume`,
  `HungerComponent.charge_all`, `GridMover.speed_scale`, ...) so they're
  correct against the codebase as it stands, but nothing instantiates them yet
  — no `.tscn` scenes, no input bindings, no call sites in `Enemy`/`Player`.
- Every such gap is called out inline as **"not yet wired"** at its exact
  integration point, mirroring how slice 1's own design doc flagged
  `EnemyType.skills` and `excess_consumed` as seams before slice 2 built on
  them.

This mirrors the project's own convention: a design doc lays the seams, a
later playtest-iteration doc (like `2026-07-09-grid-melee-webs-devtools-
iteration.md`) does the wiring and records the judgment calls.

## 1. Architectural blueprint

```
                    ┌─────────────────────────────────────────┐
                    │              GameState                   │
                    │  depth, run_seed, depth_scale()           │
                    │  runes, purchased_upgrades (NEW)          │
                    └───────────────┬───────────────────────────┘
                                    │ read by
        ┌───────────────────────────┼────────────────────────────┐
        │                           │                            │
   ┌────▼─────┐              ┌──────▼───────┐            ┌───────▼────────┐
   │   MAP    │              │   ENTITIES   │            │  SPECIALISATION │
   │          │              │              │            │                 │
   │ MazeData │◄─pit/wall────┤ Enemy (FSM + │◄──kit from─┤ SpiderClassData │
   │  +pits   │   overlay    │ EnemyUtilityAI)           │  (4 classes)    │
   │  (NEW)   │              │ Player       │            │  skill_scenes[] │
   │          │              │ Larva +      │            └───────┬─────────┘
   │ CeilingData             │  LarvaGrowth │                    │ instances
   │  (NEW)   │              │ Earthworm    │            ┌───────▼─────────┐
   │          │              │  (hazard     │            │  SkillComponent  │
   │ Level    │              │  creature)   │            │  (base, NEW)     │
   │ .Layer   │              └──────┬───────┘            │  8 concrete      │
   │ enum,    │                     │ owns                │  skills (NEW)    │
   │ is_blocked                     │                      └───────┬─────────┘
   │ (NEW)    │              ┌──────▼───────┐                     │ read/write
   └────┬─────┘              │ StatusEffect  │◄────────────────────┘
        │                     │ Component     │
        │ scheduled by        │  (NEW, unified│
   ┌────▼─────────┐           │  buff timer)  │
   │HazardDirector │◄─────────┴───────┬────────┘
   │  (NEW)        │                  │ applies to
   │ WaterIngress  │           ┌──────▼───────┐
   │ Seismic       │           │  ITEMS/PREY   │
   │ Compaction    │           │               │
   │ Centipede     │           │ PreyType (NEW)│
   │ Express       │           │ ConsumableItem│
   └───────────────┘           │  Lure/Fungus×2│
                                │  /SeedPod(NEW)│
                                │ UpgradeCatalog│
                                └───────────────┘
```

Five subsystems, one shared spine:

- **Map** owns tile truth (`MazeData` + its new pit overlay, `CeilingData`).
  `Level` exposes the one seam (`is_blocked(tile, plane)`) everything else
  reads through, so ground and ceiling stepping — and every hazard that edits
  tiles — stay consistent with what's actually rendered/pathed.
- **Entities** (Enemy/Player/Larva/Earthworm) are unchanged this pass except
  for new, detachable components (`LarvaGrowth`, `EnemyUtilityAI`) they don't
  yet own.
- **Specialisation** is data (`SpiderClassData`) + behaviour
  (`SkillComponent` subclasses), composed the same way `EnemyType` already
  composes stats — author a Resource, don't fork the scene.
- **Items/Prey** are data (`PreyType`, `ConsumableItem`) that write into the
  same `StatusEffectComponent` slot every skill does, so a Poison from a
  Fungal Larva and a Poison from a Net-Caster's net are the same code path.
- **Hazards** are scheduled `Level`-tile edits, gated by the same
  `MazeData.is_boundary()` guardrail the new player-facing wall-removal skill
  uses — one guardrail, three call sites.

## 2. Guardrails — where they're actually enforced

| Guardrail (from the brief) | Enforcement point |
|---|---|
| Outer map boundaries can't be destroyed | `MazeData.is_boundary(x, y)`, consulted by `RemoveWallsSkill`, `SeismicCompaction`, `CentipedeExpress`, and `Level.collapse_tile_at()`. **Not** consulted by `Level.dev_remove_wall_at()` — that stays the unrestricted dev cheat it already was (`test_dev_remove_wall_carves_the_border_open` locks that in); production wall-editing is a separate, gated call site. |
| Camouflage breaks on any attack | `CamouflageSkill.break_camouflage()` — a single method both the attacker-side and victim-side of an attack resolution must call. Not yet wired into `Player._melee`/`WebEmitter.fire`/`Hurtbox.receive_hit` (flagged inline). |
| Unified tick-based timer for buffs (no overlapping-buff crashes) | `StatusEffectComponent`: re-applying an id refreshes it in place instead of adding a second timer for the same slot. `SilkTunnelSkill` and `SeedPodItem` both drive `GridMover.speed_scale` through it rather than `GridMover.apply_slow`'s own ad hoc timer, specifically so a Seed Pod buff and a Silk Tunnel self-buff can't fight over the same field. |
| No magic numbers | Every tunable (cooldowns, durations, radii, hazard intervals) is a named `@export`/`const` on the owning class — see the "Tunable starting values" table in §8. |
| Depth scaling can't produce an impossible fight | `EnemyUtilityAI.depth_intel()` and `HazardDirector`'s frequency scaling both read `GameState.depth_scale()`/`depth` but never touch health/damage numbers directly — those stay solely on `EnemyType`. Frequency and reaction speed scale; severity per-hit does not. |

## 3. Dual-Plane Map Architecture

- `MazeData` gained a **pit overlay** (`_pits: Dictionary`, `is_pit`,
  `set_pit`, `is_ground_blocked`) instead of a third tile-type enum value — a
  pit (or a temporary flood) is "ground blocked, ceiling unaffected", which is
  exactly what `is_ground_blocked = not is_open OR is_pit` encodes, and it's
  reused as-is by Water Ingress (§7).
- `CeilingData` wraps a `MazeData` and answers `is_open`/`is_blocked` purely
  off wall geometry — it never looks at `_pits` at all, which is the whole
  mechanism behind "ceiling travel bypasses ground hazards".
- `Level.Layer` (`GROUND`/`CEILING`) + `Level.is_blocked(tile, layer)` is the
  one seam a plane-aware `GridMover.block_check` should call through.
  `PlaneComponent` (new) tracks which layer an owner occupies and exposes
  `blocked(tile, dir)` + `transition()` for that.
- **Not yet wired:** no spider actually has a `PlaneComponent` attached, and
  no input action triggers `transition()`. Rendering a spider on the ceiling
  (visually offset, or drawn on a separate `CanvasLayer`) is unaddressed —
  the data model is ready, the visual/physics attachment isn't.

## 4. AI & Depth Scaling

- **Larvae:** `LarvaGrowth` (new component) tracks `age` → `size_scale`
  (caps at `MAX_SIZE_SCALE`) → `heal_value()`. It ticks independently of
  `caught` state, so a larva keeps aging while held in a web. Not yet attached
  to `larva.tscn`; `Enemy._eat_larva`/`Player._melee`/`WebTrap.try_consume`
  all still use the flat `eat_satiation`/`satiation` constants — swapping
  those for `LarvaGrowth.heal_value()` is the wiring step.
- **Enemy AI:** `EnemyUtilityAI` (new, `RefCounted`) scores `Action` candidates
  (`PATROL`/`SEEK_FOOD`/`CHASE`/`FLEE`/`USE_SKILL`) and returns the best one.
  It sits *above* `Enemy`'s existing enum FSM by design — `State` stays the
  execution mechanism, and `Enemy._update_state`'s hard CHASE/FLEE overrides
  stay authoritative. `depth_intel(depth)` gives a 0..1 "how aggressively
  should this enemy play" scalar for biasing skill-use weight and shrinking
  `repath_interval`, explicitly never for scaling health/damage (that stays
  on `EnemyType` + `GameState.depth_scale()` — see the guardrail table).
  Not yet consulted by `Enemy` in this pass.

## 5. Class Specialisations

`SpiderClassData` (new `Resource`) is the specialisation analogue of
`EnemyType`: `spider_class` enum, melee/web multipliers, and a
`skill_scenes: Array[PackedScene]` kit. Concrete classes are `.tres` authoring
work (`resources/spiders/net_caster.tres`, etc.), not new scripts — same
pattern `EnemyType` already established.

`SkillComponent` (new base) gives every skill cooldown + hunger cost for free,
via the same `HungerComponent.charge_all` metabolic tax every other action
already pays. Eight concrete skills:

| Class | Skill | File | Key mechanic |
|---|---|---|---|
| Net-Caster (M) | Net Hold | `net_hold_skill.gd` | Instantly resolves `WebTrap.try_consume` within reach — no walk-up needed |
| Net-Caster (M) | Net Projectile | `net_projectile_skill.gd` | Zero damage, full stun via `apply_web_hit(..., stun_duration)`; copies the shooter's `StatusEffectComponent` onto the victim |
| Wolf (F) | Hatchlings | `hatchlings_skill.gd` | Spawns N temporary scouts for a fixed lifetime |
| Wolf (F) | Egg/Cocoon Mine | `egg_mine_skill.gd` | Places a proximity mine (contract: `arm(owner, burst_count)`) |
| Weaver (M) | Blockade | `blockade_skill.gd` | Deploys a hard obstacle; also calls `Level.patch_pit_at()` if placed over a pit |
| Weaver (M) | Silk Tunnel | `silk_tunnel_skill.gd` | Lays N `WebTrap`s ahead; self-buffs speed via `StatusEffectComponent` |
| Decoy (F) | Decoy | `decoy_skill.gd` | Drops a static effigy (contract: joins `"spiders"` + `"decoys"` groups) |
| Decoy (F) | Camouflage | `camouflage_skill.gd` | Near-invisible; `break_camouflage()` is the guardrail hook (§2) |

**Not yet wired:** none of the eight have an authored `.tscn` for their
projectile/mine/hatchling/decoy visuals, and no `Player`/`Enemy` input path
calls `SkillComponent.activate()` yet.

## 6. Skills & Utilities

Two general-purpose (non-class-locked) skills, same `SkillComponent` base:

- `SenseSkill` — applies a timed `&"sense"` tag via `StatusEffectComponent`.
  Actually rendering x-ray vision (ignoring `LightOccluder2D` while the tag is
  active) is an extension point on `MazeRenderer`/`Level.apply_darkness()`,
  not built here.
- `RemoveWallsSkill` — the production-facing counterpart to
  `World._dev_remove_wall`. Same underlying `Level.dev_remove_wall_at()` carve
  mechanism, but boundary-gated via `Level.is_boundary()` first — the dev
  cheat itself is untouched (see the guardrail table in §2 for why).

## 7. Economy, Power-ups & Currency

- `GameState.runes` (+ `earn_runes`/`spend_runes`/`buy_upgrade`) is a new,
  session-long balance — deliberately **not** reset by `start_new_run()`,
  exactly like `player_wins`/`enemy_wins` already aren't. "Permanent" upgrade
  here means "for this session"; true cross-run persistence needs a save
  system this project doesn't have yet (explicitly out of scope, not silently
  assumed).
- `UpgradeCatalog` (new `Resource`) is one purchasable entry;
  `GameState.buy_upgrade()` is the only spend path and records
  `purchased_upgrades` to prevent double-charging.
- `ConsumableItem` (new base `Resource`) + four concrete items:

  | Item | File | Effect |
  |---|---|---|
  | Lure | `lure_item.gd` | Not a pickup — `draw_larvae_within()` queries nearby larvae for a placed lure's own script to steer (steering itself is an extension point; `Larva._wander_step()` has no path-toward-a-point seam yet) |
  | Fungus (Poison) | `fungus_poison_item.gd` | Grants the eater a `&"venomous"` tag; static `apply_venom_on_hit(attacker, victim)` is the call every attack path should make after landing a hit (not yet wired) |
  | Fungus (X / Sense) | `fungus_sense_item.gd` | Applies the same `&"sense"` tag `SenseSkill` does, at zero action cost |
  | Seed Pod | `seed_pod_item.gd` | `&"seed_haste"` tag driving `GridMover.speed_scale`, same pattern as `SilkTunnelSkill` |

## 8. Edible Creature Variation

`PreyType` (new `Resource`) is the prey analogue of `EnemyType`: `hunger_value`,
`edible`, and an optional `on_eaten_status_id`/`magnitude`/`duration` hook.
Concrete variants are `.tres` authoring work under `resources/prey/`, not new
scripts:

| Variant | `hunger_value` | `on_eaten_status_id` | Notes |
|---|---|---|---|
| Normal Larva | (slice-1 default) | — | No hook — the existing baseline |
| Fungal Larva | (slice-1 default) | `&"venomous"` | Reuses Fungus Poison's tag |
| Beetle | small | `&"armor"` | 60s flat mitigation — **extension point**: `HealthComponent.take_damage` doesn't consult a status tag yet; this pass leaves that core, heavily-tested file untouched and documents the hook instead of wiring it blind |
| Ant | small | `&"seed_haste"` | Reuses Seed Pod's tag |
| Cicada Nymph [Rare] | small | — | `reveals_location = true` → `EventBus.location_revealed` (new signal) |

`Earthworm` (new entity, `entities/earthworm/earthworm.gd`) is the inedible
hazard/obstacle: `BLOCKING` until `hits_to_flee` melee hits, then
`RETREATING` — walks toward the nearest map-boundary side and despawns on
arrival. It never actually leaves the maze grid (`global_position` just exits
the map's pixel rect); "burrows out of map bounds" is flavour for "despawns
at the edge", so the boundary guardrail is never at stake here. Not yet
instanced by `Level`, and `take_hit()` isn't yet called from
`Player._melee`/`Enemy` melee.

## 9. Dynamic Environment Seeding

`HazardEvent` (new base, `RefCounted`) + three concrete hazards + a
`HazardDirector` (new `Node`) that schedules them against a bound `Level`:

- **Water Ingress** (`water_ingress.gd`) — floods a radius of open,
  non-boundary tiles via `MazeData.set_pit(..., true)`, recedes after
  `FLOOD_DURATION` via a `SceneTree` timer. Reuses the pit overlay rather than
  a fourth tile state.
- **Seismic Compaction** (`seismic_compaction.gd`) — opens `OPEN_COUNT` random
  walls, collapses `COLLAPSE_COUNT` random unoccupied open tiles (via the new
  `Level.collapse_tile_at()`, the exact inverse of `dev_remove_wall_at`).
  Both passes skip `is_boundary()` tiles.
- **Centipede Express** (`centipede_express.gd`) — clears a full row or column
  in one sweep, skipping the boundary. Net corridor-adding only, unlike
  Seismic Compaction's net-neutral redraw.
- `HazardDirector` scales **frequency** by `GameState.depth_scale()`; each
  hazard's own severity constants are fixed (guardrail table, §2).

**Not yet wired:** `HazardDirector` isn't instanced anywhere — attach it as a
child of `Level` and call `bind_level(self)` from `Level.build()` to turn it
on.

## 10. New/changed files

**New:**
`components/status_effect_component.gd`, `components/skill_component.gd`,
`components/plane_component.gd`, `entities/larva/larva_growth.gd`,
`entities/earthworm/earthworm.gd`, `entities/enemy/enemy_utility_ai.gd`,
`world/maze/ceiling_data.gd`, `world/hazards/{hazard_event,water_ingress,
seismic_compaction,centipede_express,hazard_director}.gd`,
`resources/{spider_class_data,prey_type,consumable_item,upgrade_catalog}.gd`,
`resources/items/{lure_item,fungus_poison_item,fungus_sense_item,
seed_pod_item}.gd`, `entities/skills/{net_hold_skill,net_projectile_skill,
hatchlings_skill,egg_mine_skill,blockade_skill,silk_tunnel_skill,decoy_skill,
camouflage_skill,sense_skill,remove_walls_skill}.gd`.

**Changed (additive only — no existing behaviour altered):**
- `MazeData`: `is_boundary`, `set_wall`, `is_pit`/`set_pit`/`is_ground_blocked`.
- `Level`: `Layer` enum, `ceiling` field, `_ready()` joins `"level"` group,
  `is_boundary`, `is_blocked`, `patch_pit_at`, `collapse_tile_at`;
  `_build_collision_and_occluders` refactored to share `_spawn_wall_node()`
  with `collapse_tile_at`.
- `EventBus`: `runes_changed`, `plane_changed`, `hazard_triggered`,
  `status_effect_applied`/`status_effect_expired`, `location_revealed`.
- `GameState`: `runes`, `purchased_upgrades`, `earn_runes`, `spend_runes`,
  `buy_upgrade`.

## 11. Testing

Pure logic gained unit coverage (37 new tests, all passing alongside the
existing 144): `MazeData` pit/boundary/wall mutators
(`test_maze_pits_and_boundary.gd`), `CeilingData` (`test_ceiling_data.gd`),
`StatusEffectComponent` including the refresh-not-stack guardrail
(`test_status_effect_component.gd`), `LarvaGrowth`
(`test_larva_growth.gd`), `GameState` runes/upgrades
(`test_game_state_runes.gd`), and `Level`'s new plane/hazard helpers
(`test_level_hazard_helpers.gd`).

Skills, items, and hazards that reach into not-yet-authored scenes
(`net_shot_scene`, `hatchling_scene`, decoy/mine visuals, ...) are
integration-only by nature and untested here, matching the original design
doc's own §9: "scene-level behaviour is verified by running the game, not
unit tests." A headless boot of `world.tscn` (600 frames) is clean.

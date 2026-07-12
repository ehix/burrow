# Hatchlings / VFX / Generic Skill Input — Design

## Context

Second round of playtest feedback, following on from the already-merged
Skill Fixes Bundle (sub-project E) and UI/HUD Overhaul (sub-project I). Five
issues, spanning three loosely-related areas — Hatchlings' escort AI and
lifecycle, the shared outline shader plus how Sense/Camouflage use it, and
the per-class skill keybinding scheme — bundled into one round the same way
sub-project E bundled six unrelated skill fixes into one PR.

Scope: `components/skill_component.gd`, `entities/skills/hatchlings_skill.gd`,
`entities/skills/scenes/tiny_spiderling.gd`/`.tscn`,
`entities/skills/sense_skill.gd`, `entities/skills/camouflage_skill.gd`,
`components/outline_fx.gd`, `assets/shaders/outline.gdshader`,
`world/level.gd`, `entities/player/player.gd`, `ui/control_indicators.gd`,
`ui/skill_bar.gd`, `project.godot`, and their tests.

**Branch base:** this branch is stacked on top of the not-yet-merged
`ui-hud-overhaul` branch (PR #10), not `main` — `SkillBar` (see item 5
below) only exists there, and this round needs to touch it.

## Current state

- **Hatchlings** (`hatchlings_skill.gd` + `scenes/tiny_spiderling.gd`):
  spawns `spawn_count` `TinySpiderling`s that escort near the caster (walking
  toward `owner.global_position + escort_offset`, no distance cap — if one
  gets stuck on wall geometry the gap just keeps growing) until an enemy
  enters `aggro_radius` + line-of-sight, then chases/attacks it. Each one
  self-frees after a fixed `lifetime` (8s), regardless of combat state.
  `TinySpiderling` has no `Hurtbox`/`HealthComponent` — it can deal damage
  but never receive it, so nothing can kill it in combat today.
  `SkillComponent.activate()` arms `_cooldown_left = cooldown` unconditionally
  before `_on_activate()` runs, with no hook for a subclass to defer that.
- **Outline shader** (`assets/shaders/outline.gdshader` +
  `components/outline_fx.gd`): a 4-tap (N/S/E/W only) alpha-edge outline —
  for a transparent fragment, if a same-distance cardinal neighbor is
  opaque, paint `outline_color`. No diagonal samples, so diagonal edges/
  corners read thin. `OutlineFx.set_outline()` is refcounted per-sprite
  (Camouflage and Sense both call it on the same sprites without
  double-toggling each other off).
- **Camouflage** (`camouflage_skill.gd`): sets `_visual.modulate.a =
  target_alpha` (0.15) directly on the sprite node, alongside
  `OutlineFx.set_outline(_visual, true, ...)`. Since Godot's `modulate`
  multiplies the *entire* `COLOR` a canvas_item shader outputs, this dims
  the outline along with the body — there's no way today to have a faint
  body and a fully-visible outline at once.
- **Sense** (`sense_skill.gd` + `world/level.gd`): applies a timed `"sense"`
  status tag. `Player._on_effect_applied`/`_on_effect_expired` relay it to
  two `Level` calls: `set_sense_active()` (hides every wall's
  `LightOccluder2D` so the player's vision light passes through walls —
  the "illuminates the map" effect that reads wrong) and
  `set_sense_outline()` (a one-shot blanket toggle of `OutlineFx` on every
  spider/larva in the level, no radius limit, no per-frame tracking as the
  player moves). Walls have no per-tile visual node to outline — the whole
  maze is drawn by one batched `MazeRenderer`; `_wall_nodes[tile]` only
  tracks `{collision, occluder}`, no sprite.
- **Skill input** (`entities/player/player.gd` + `project.godot`): 8
  distinct actions (`camouflage`, `net_hold`, `net_shot`, `hatchlings`,
  `egg_mine`, `blockade`, `silk_tunnel`, `decoy`), each bound to its own key
  (V/B/T/Y/U/O/I/Z), each checked individually in `_physics_process()` via
  `Input.is_action_just_pressed("<name>")` (or `is_action_pressed` for the
  one held skill, `net_hold`) gated by `_is_active_skill("<name>")`.
  `Player.active_skills()`/`SkillBar`/`CLASS_SKILLS` already resolve
  generically off whatever action-name keys `CLASS_SKILLS` lists — only the
  input-polling block and the dev debug overlay
  (`ui/control_indicators.gd`) hardcode the 8 individual names.

## Design

### 1. Hatchlings: tighter escort + snap, real death, death-triggered cooldown

`TinySpiderling._escort()` gains a `leash_distance: float = 200.0` export.
Today it always walks toward `owner + escort_offset`; once the distance to
that spot exceeds `leash_distance` (e.g. stuck on a corner while the owner
moves away), it teleports directly there instead of continuing to path —
one mechanism that bounds both "not tight enough" and "stuck on corners".

`TinySpiderling` gains a `Hurtbox` (Area2D) + `HealthComponent` child with
`max_health = 1`, wired the same way Player/Enemy already are — any hit
from any attack type (melee, web, mine) kills it in one shot through the
existing damage pipeline (`Hurtbox.receive_hit()` → `HealthComponent
.take_damage()` → `died` signal → `queue_free()`), rather than a
narrower Larva-style duck-typed `web_kill()` that would only respond to
web shots.

The fixed `lifetime` timer is removed entirely — hatchlings persist until
killed in combat.

`SkillComponent` gains a small extension point for cooldown timing:

```gdscript
var _busy: bool = false

func can_activate() -> bool:
    return not _busy and _cooldown_left <= 0.0

func activate(source: Node) -> bool:
    if not can_activate():
        return false
    if _defer_cooldown():
        _busy = true
    else:
        _cooldown_left = cooldown
    HungerComponent.charge_all(source.get_tree(), hunger_cost)
    _on_activate(source)
    return true

func _defer_cooldown() -> bool:
    return false

## Subclasses that returned true from _defer_cooldown() call this once
## ready to start the real cooldown countdown.
func _start_deferred_cooldown() -> void:
    _busy = false
    _cooldown_left = cooldown

func remaining_cooldown() -> float:
    return cooldown if _busy else _cooldown_left
```

`HatchlingsSkill` overrides `_defer_cooldown()` to return `true`, tracks its
spawned batch in an array, connects each hatchling's `tree_exited` signal,
and calls `_start_deferred_cooldown()` once the batch is empty. While the
batch is alive, `SkillBar` shows the skill dimmed with the frozen full
`cooldown` value (via `remaining_cooldown()`'s `_busy` branch above); once
the last hatchling dies, it starts counting down for real.

### 2. Outline shader: thicker, no more diagonal thinness

`assets/shaders/outline.gdshader` adds the 4 diagonal samples (8-tap total:
N/S/E/W + NE/NW/SE/SW) alongside the existing cardinal ones, and the default
`outline_width` goes `1.0` → `2.0`. Same technique, full edge coverage.

### 3. Camouflage: decouple body opacity from the outline

Body-dimming moves out of node `modulate` and into the shader, so it can no
longer drag the outline down with it. New uniform in `outline.gdshader`:

```glsl
uniform float body_alpha : hint_range(0.0, 1.0) = 1.0;
```

Applied only to normal (non-outline) body pixels — the outline branch keeps
using `outline_color`'s own alpha untouched. `OutlineFx` gains
`set_body_alpha(sprite: CanvasItem, alpha: float) -> void`, following the
same lazy-material-creation pattern `set_outline()` already uses.
`CamouflageSkill` stops touching `_visual.modulate.a`; instead calls
`OutlineFx.set_body_alpha(_visual, target_alpha)` (still `0.15`) on
activate, and `OutlineFx.set_body_alpha(_visual, 1.0)` on
`break_camouflage()`.

### 4. Sense: outline-only, radius-limited, includes walls (future-proofed)

`Player._on_effect_applied`/`_on_effect_expired` stop calling
`Level.set_sense_active()` — that method and the wall-occluder-hiding
behavior it drives are removed. No more vision-light-through-walls.

`SenseSkill` gains a `radius: float = 240.0` export. `Level`'s outline
handling becomes continuous and radius-limited instead of a one-shot
blanket toggle:

- `Level` tracks `_sense_active: bool` and `_sense_radius: float`, set by
  `set_sense_outline(active, radius)` (signature gains `radius`).
- While active, `Level._process()` (already exists, for larva spawning)
  recomputes each frame which spiders/larvae are within `radius` of the
  player and which are not, toggling `OutlineFx.set_outline()` per node
  only on entry/exit (tracked via a `_sense_outlined: Dictionary` of
  currently-on nodes, since `OutlineFx` is refcounted and needs matched
  on/off calls) — not per-frame regardless of change, so it doesn't spam
  redundant ref-count churn.
- All spider/larva outlines clear when `set_sense_outline(false, ...)` is
  called on expiry.

**Walls**: the alpha-edge outline technique fundamentally depends on walls
being visually opaque against a transparent/background floor — true for
today's placeholder `MazeRenderer` draw, but not something to build on,
since real map art (planned separately) will make floor tiles opaque too
and break that assumption entirely. So walls get a different, art-agnostic
mechanism: a lightweight translucent highlight node (e.g. a `ColorRect`
sized to `TILE_SIZE`) added as a sibling of each wall tile's existing
`_wall_nodes[tile]` entry, toggled on/off per-tile the same
entry/exit-tracked way as the entity outlines above (`_sense_wall_highlights:
Dictionary`, tile → highlight node). This only needs "is this tile
coordinate a wall within radius" — never touches or assumes anything about
what's actually drawn there, so it keeps working unchanged whether walls
are today's placeholder shapes or later real tile sprites.

### 5. Generic two-button skill input

`project.godot`: remove the 8 per-class actions (`camouflage`, `net_hold`,
`net_shot`, `hatchlings`, `egg_mine`, `blockade`, `silk_tunnel`, `decoy`).
Add two generic actions:

| action | physical_keycode | key |
|---|---|---|
| `skill_1` | 86 | V |
| `skill_2` | 66 | B |

`Player._physics_process()`'s 7 separate per-action blocks collapse to two,
resolving positionally through `CLASS_SKILLS[_active_class]`:

```gdscript
var skills: Array = CLASS_SKILLS.get(_active_class, [])
if skills.size() > 0 and Input.is_action_pressed("skill_1"):
    _skill_by_action.get(skills[0]).activate(self)
if skills.size() > 1 and Input.is_action_just_pressed("skill_2"):
    _skill_by_action.get(skills[1]).activate(self)
```

`skill_1` polls with `is_action_pressed` (not `_just_pressed`) so it works
uniformly whether the current class's first skill is a held skill
(`NetHoldSkill`, whose own `activate()` override already no-ops harmlessly
on repeat calls while already holding or with nothing in reach) or a
one-shot skill (cooldown-gated, so repeat calls while held are harmless —
`can_activate()` blocks re-trigger after the first). `skill_2` never lands
on a held skill in the current `CLASS_SKILLS` layout, so it stays
`_just_pressed` for a clean single-trigger feel.

`Player.active_skills()`, `CLASS_SKILLS`, and the class-switching tests are
untouched — they already key off whatever action names `CLASS_SKILLS`
lists, not the two new input actions.

**`ui/skill_bar.gd` (from the not-yet-merged UI/HUD Overhaul branch, which
this branch is based on) needs one fix**: `_bind_slot()` currently looks up
each slot's displayed keybind via `InputMap.action_get_events(action)`,
where `action` is the literal per-skill name (`"hatchlings"`, etc.) returned
by `active_skills()`. Once those 8 actions are removed from `project.godot`,
that lookup returns nothing and every slot's key label goes blank.
`_rebind()` already knows each skill's *positional* slot (`action1`/
`action2`, i.e. index 0/1 into `CLASS_SKILLS[class]`) — `_bind_slot()`'s
`InputMap` lookup changes to use `"skill_1"`/`"skill_2"` (passed in
alongside or instead of the per-skill action name) rather than the
per-skill action string, while `skill.display_name`/`.description` (which
come from the `SkillComponent` itself, not `InputMap`) are unaffected.

`ui/control_indicators.gd`'s 8 hardcoded one-shot entries
(`"Camouflage (V)" -> "camouflage"`, etc.) are replaced with two entries
built dynamically from `Player.active_skills()` + `InputMap
.action_get_events("skill_1"/"skill_2")`, so the debug overlay keeps
showing the right skill name/key for whichever class is active instead of
listing all 8 skills at once with now-nonexistent per-skill bindings.

## Testing

- `tests/test_tiny_spiderling.gd`: escort snaps to the desired position
  once distance exceeds `leash_distance` instead of continuing to path;
  dies in one hit via `Hurtbox.receive_hit()`; no longer despawns from a
  `lifetime` timer.
- `tests/test_skill_component.gd`: new `_defer_cooldown()`/
  `_start_deferred_cooldown()`/`_busy` behavior on the base class — a
  non-deferred skill's `activate()`/`can_activate()`/`remaining_cooldown()`
  behavior is unchanged; a deferred skill stays non-reactivatable and shows
  the frozen `cooldown` value until `_start_deferred_cooldown()` is called.
- `tests/test_hatchlings_skill.gd`: cooldown doesn't start counting down
  until every spawned hatchling has left the tree; starts counting down for
  real once the last one is gone.
- `tests/test_outline_fx.gd`: extend for `set_body_alpha()` — sets/updates
  the uniform, independent of `set_outline()`'s own state.
- `tests/test_camouflage_wiring.gd`: activating sets `body_alpha` to
  `target_alpha` (not `modulate.a`); breaking resets it to `1.0`.
- `tests/test_level_sense_and_pits.gd` (or wherever `set_sense_active`
  coverage lives): remove/update tests tied to the removed method.
- New/extended `Level` test: `set_sense_outline(true, radius)` outlines
  only spiders/larvae within `radius` of the player, updates as the player
  moves closer/further (entry/exit), and clears everything on
  `set_sense_outline(false, ...)`; wall highlights appear/disappear the
  same way for wall tiles within radius.
- New `tests/test_player_skill_input.gd`: pressing `skill_1`/`skill_2`
  dispatches to the correct `SkillComponent` for whichever class is
  currently active (covering at least two different classes to prove the
  positional resolution, not a hardcoded name).
- `tests/test_player_class_switching.gd`: unaffected (asserts against
  `CLASS_SKILLS`/`active_skills()`, not input actions) — confirm as part of
  the round, not expected to need edits.
- Outline shader's diagonal-sampling change is shader logic, not
  GUT-testable — covered by the manual playtest pass only.
- Headless validation per the existing workflow: import check, then a
  throwaway scene run.

## Out of scope

- Real multi-hit HP for hatchlings — one-hit-kill via a 1-HP `Hurtbox` was
  the chosen simplicity, not a health-bar minion.
- Any change to `spawn_count`/`spawn_radius`/attack stats for Hatchlings.
- A soft glow/bloom shader style — the crisp, thicker-edge outline was the
  chosen direction.
- Enemy's own Sense-equivalent (Enemy has no `SenseSkill` today, unaffected
  by this round).
- Rebalancing `hunger_cost`/`cooldown` seconds for any skill — only the
  mechanics described above change, not the tuning numbers, beyond the new
  `leash_distance`/`radius` exports this design introduces.
- Actually adding real map/tile art — mentioned by the user as planned
  future work; this design only makes the wall-highlight mechanism
  resilient to that future change, it doesn't implement the art itself.

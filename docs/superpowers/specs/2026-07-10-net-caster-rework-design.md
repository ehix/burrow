# Net-caster Rework — Design

## Context

Raw playtest feedback flagged the Net-caster class as "completely wrong": it
currently has no trap-carrying mechanic at all. This is sub-project A of a
much larger feedback packet (UI overhaul, other class fixes, larvae/centipede
work, plane mechanics, environment tiles, skills/items) that was explicitly
decomposed into independent slices — see the conversation this spec came
from for the full breakdown. This slice replaces only the Net-caster's two
class skills; it does not touch UI, other classes, or any other module.

## Current state

- `place_trap` (generic action, unchanged by this spec) lays a `WebTrap` via
  `TrapPlacer` — any class can do this today and will continue to.
- `NetHoldSkill` (`entities/skills/net_hold_skill.gd`) remotely harvests an
  already-caught larva from a nearby trap within `reach` — there is no
  "pick up" concept at all.
- `NetProjectileSkill` (`entities/skills/net_projectile_skill.gd`) fires a
  slow (300 px/s) net projectile (`entities/skills/scenes/net_shot.gd/.tscn`,
  collision mask 17 = world + hurtbox only, blind to larvae/traps) that hard
  -immobilizes a hit spider for 2.5s and copies the victim's active status
  effects onto them.
- Both skills are used by `Player` (input-driven, `entities/player/player.gd`)
  and `Enemy` (utility-AI-driven via `_score_skill`/`_make_skills`,
  `entities/enemy/enemy.gd:185-206,363-408`).
- `NET_CASTER`'s `web_enabled = false` (`resources/spiders/net_caster.tres`)
  — they have no ordinary web shot today, and won't gain one from this spec.

## New behavior

### Net Hold (`entities/skills/net_hold_skill.gd`, rewritten)

Pressing it (subject to the existing `SkillComponent` cooldown/hunger gate)
looks for the nearest trap the entity itself placed, within `reach`, among
`get_tree().get_nodes_in_group("traps")`. If found:

- The placed `WebTrap` node is freed and a `holding: bool` flag turns on.
- If that trap already held a caught larva, it is eaten immediately as part
  of the pickup, using the same satiation flow `WebTrap.try_consume` uses
  (`HungerComponent.satiate(caught_larva.heal_value())`, `EventBus`
  `larva_consumed`/`excess_consumed`).
- While `holding` is true, a lightweight placeholder visual (matching the
  existing draw-a-shape convention used by `NetShot`/`CombatFx`) tracks one
  tile ahead of the entity's facing (`source.get("facing")`, duck-typed the
  same way `NetProjectileSkill` already does) every `_physics_process`,
  using `tile_size` read off the entity's sibling `GridMover`.
- If a larva's tile matches that forward tile, it is eaten immediately
  (same satiation flow) and `holding` turns back off.
- No manual drop. Holding only resolves two ways: a larva walks into it, or
  Net Shot spends it. This is deliberately the simplest reading of the
  feedback.

Public surface other skills need: `is_holding() -> bool` and an internal way
for `NetShotSkill` to consume the held state when it fires (a `spend()`-style
method, or `holding` set directly since both live in the same package — the
implementer should pick whichever keeps `NetHoldSkill`'s invariants
enforced, e.g. always tearing down the visual node when holding ends).

### Net Shot (rename `net_projectile_skill.gd` → `net_shot_skill.gd`, class
`NetProjectileSkill` → `NetShotSkill`; rewrite `scenes/net_shot.gd`/`.tscn`)

`NetShotSkill` gets a plain `net_hold: NetHoldSkill` property (not a
`NodePath` — `Enemy._make_skills()` constructs skills dynamically via
`.new()`, so this is set explicitly by whichever caller wires the pair up).

`_on_activate()` only proceeds if `net_hold.is_holding()` is true; otherwise
it's a no-op (importantly: no cooldown/hunger is spent on a no-op — check
this before calling into the base `activate()`'s cost logic, or refund it,
whichever the existing `SkillComponent.activate()` contract makes cleaner).
On a real activation:

- The held trap is spent (`net_hold`'s holding state clears, visual torn
  down).
- A projectile spawns along facing, reusing `NetProjectileSkill`'s existing
  spawn plumbing (`_spawn_parent`, `muzzle_offset`).
- The projectile (`net_shot.gd`/`.tscn`) becomes a fast variant of `WebShot`:
  collision mask widened from 17 to 57 (adds larva=8, trap=32, matching
  `WebShot`'s own mask) and default `speed` raised well above `WebShot`'s
  340 (well above bog-standard web-shot speed — exact tuning number is an
  implementation-time call, not fixed by this spec).
- **On a larva hit:** instead of `web_kill()`, spawn a `WebTrap` at the
  impact position, `setup()` it to the shooter, and call `catch_larva()` on
  it — a live capture using the exact same machinery a normally-placed trap
  uses (including its own auto-consume-if-a-spider-is-standing-there path).
  This preserves the class's "catch, don't kill" identity.
- **On a spider hit:** unchanged from today — `NetShotSkill.resolve_hit()`
  keeps the existing hard 2.5s immobilize (`apply_web_hit(Vector2i.ZERO,
  1.0, 0.0, immobilize_duration)`) plus `_copy_status_effects()`. This was
  an explicit call: preserve the current unique mechanic rather than
  downgrade it to a plain entangle.
- **On a wall/trap/blockade hit:** resolves like `WebShot` does today (splat
  + despawn on a wall; `take_web_hit()`/`take_hit()` on a trap/blockade).

### Wiring

- `entities/player/player.gd`: rename `@onready var _net_projectile:
  NetProjectileSkill` → `_net_shot: NetShotSkill`; in `_ready()`, wire
  `_net_shot.net_hold = _net_hold`.
- `entities/player/player.tscn`: rename the `NetProjectileSkill` node to
  `NetShotSkill` (script swap).
- `entities/enemy/enemy.gd`: in `_make_skills()`'s `NET_CASTER` branch,
  construct both skills and wire `shot.net_hold = hold` before returning
  `[hold, shot]`.

### Input action rename

`net_projectile` → `net_shot` throughout: `project.godot`'s `[input]`
section, `player.gd`'s `Input.is_action_just_pressed(...)` call and
`CLASS_SKILLS` map entry, `enemy.gd` (if it references the action name
anywhere — it currently drives skills directly rather than through
`Input`, so this may only matter for `player.gd`/tests), and any test/dev
-tool references. Cosmetic, but keeps the name honest now that the
mechanic itself changed — this was a judgment call made during design, not
requested verbatim in the raw feedback.

### Enemy AI scoring (`entities/enemy/enemy.gd:363-408`)

- `_score_skill()`'s `NetHoldSkill` branch: still scores during
  `SEEK_FOOD`, but the condition changes from "is there a nearby trap with
  a caught larva" (`_nearest_caught_trap()`) to "is there a nearby trap I
  placed, ready to be picked up" (any of my own unspent traps within reach,
  not just already-loaded ones).
- `_score_skill()`'s `NetShotSkill` branch (renamed from the
  `NetProjectileSkill` check): only scores when `_active_class_data` is
  `NET_CASTER` and the enemy is actually holding a trap
  (`net_hold.is_holding()`) — firing empty-handed is never worth scoring
  since it'd no-op.
- `_nearest_caught_trap()` helper either gets renamed/generalized to
  "nearest own ready trap" or gains a sibling helper — implementer's call,
  whichever keeps the two call sites (Net Hold scoring vs. the pickup logic
  itself) from duplicating the "traps I own, within reach" scan.

## Explicit decisions from review

1. Net Shot vs. spider: **keep the current hard immobilize + status-effect
   copy**, not a downgrade to plain entangle.
2. No manual drop of a held trap.
3. A pre-loaded trap is auto-eaten on pickup, not carried loaded.

## Out of scope for this slice

- Skill icons, cooldown UI, button consolidation (Module 1 — separate
  sub-project).
- Any other class's mechanics (Weaver web-immunity, Decoy shot tuning,
  etc. — sub-project B).
- `place_trap` itself is unchanged.

## Testing

- Rewrite `tests/test_net_projectile_skill.gd` (rename to
  `test_net_shot_skill.gd`) to cover: no-op when not holding; hard immobilize
  + status-copy on a spider hit; capture-not-kill on a larva hit (spawns a
  live, consumable `WebTrap`); held state clearing after firing.
- New test for `NetHoldSkill`: pickup of a ready trap within reach, no
  pickup when out of reach or trap isn't owned by the entity, auto-eat of a
  pre-loaded trap's larva on pickup, auto-eat when a larva touches the held
  forward tile, `is_holding()` transitions.
- Update `tests/test_enemy_class_kit.gd` for the renamed
  `NetShotSkill`/`net_shot` references and the new scoring conditions.
- Manual verification in a running Godot session (headless boot/scene
  smoke test per the project's Godot validation workflow): cycle to
  Net-caster, place a trap, Net Hold to pick it up, walk a larva into it,
  confirm it's eaten; place another, pick it up, fire Net Shot at a larva
  and confirm it's caught (not killed) and consumable; fire Net Shot at the
  rival spider and confirm the hard immobilize.

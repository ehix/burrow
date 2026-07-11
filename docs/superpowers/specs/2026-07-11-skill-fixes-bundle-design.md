# Skill Fixes Bundle — Design

## Context

Playtest feedback flagged six independent issues across four skills: Sense
and Camouflage both wanted an "outline" visual treatment; Hatchlings felt
slow, omniscient (chases through walls), and either idle or aggressive with
nothing in between; Egg Mine needed to spare larvae, support ceiling
placement, and hit harder; Silk Tunnel felt too short; Decoy could trap its
own caster on placement. This is sub-project E of the larger feedback packet
decomposition (see the Item/Inventory Rework spec for the full breakdown) —
six small-to-medium, largely-independent fixes bundled into one round,
matching how sub-project B bundled four class-identity fixes into one PR.

Two items scoped in the original roadmap turned out to already be built,
discovered while reading the current code rather than trusting the roadmap
text: Camouflage's attack-break wiring (`Hurtbox.receive_hit()` →
`CamouflageSkill.break_if_present()` on both sides, already tested in
`tests/test_camouflage_wiring.gd`) and Decoy's AI retargeting
(`Enemy._acquire_target()` already prefers a nearer visible decoy over the
real player, tested in `tests/test_enemy_decoy_diversion.gd`). Both are
excluded from this round's scope below.

Scope: `entities/skills/sense_skill.gd`, `entities/skills/camouflage_skill.gd`,
`entities/skills/hatchlings_skill.gd`, `entities/skills/egg_mine_skill.gd`,
`entities/skills/silk_tunnel_skill.gd`, `entities/skills/scenes/decoy.gd`/
`.tscn`, `entities/skills/scenes/tiny_spiderling.gd`,
`entities/skills/scenes/cocoon_mine.gd`, a new shared outline shader, a new
cosmetic-burst scene for Egg Mine, and their tests.

## Current state

- **Sense** (`sense_skill.gd`): already applies a timed `"sense"` status tag,
  which `Player._on_effect_applied`/`_on_effect_expired` relay to
  `Level.set_sense_active()` — this hides every wall's light occluder while
  active, letting the vision light pass through nearby walls (tested,
  `tests/test_level_sense_and_pits.gd`). No entity-level visual cue exists
  for what's been revealed.
- **Camouflage** (`camouflage_skill.gd`): fades the caster's `Sprite2D` alpha
  to `target_alpha` (0.15) for `duration`, and already breaks the instant an
  attack lands on either side via `Hurtbox.receive_hit()` →
  `CamouflageSkill.break_if_present()`. No outline/silhouette treatment
  exists.
- **Hatchlings** (`hatchlings_skill.gd` + `scenes/tiny_spiderling.gd`):
  spawns `spawn_count` `TinySpiderling`s in a radial pattern around the
  caster. Each one runs `_nearest_target()` — nearest node in the `"spiders"`
  group by raw distance, no line-of-sight check, no wall awareness — and
  either chases (if a target exists) or sits at `velocity = Vector2.ZERO`
  (if not). `move_speed` is `90`, well under Player's ~400px/s or Enemy's
  ~300px/s effective step speed.
- **Egg Mine** (`egg_mine_skill.gd` + `scenes/cocoon_mine.gd`): spawns a
  `CocoonMine` at the caster's ground position (no plane-awareness).
  `_on_body_entered` triggers on any `"spiders"` or `"larvae"` body except
  the owner, bursting `_burst_count` `TinySpiderling`s (the same
  full-chase-AI entity Hatchlings uses) around itself. No direct damage is
  dealt by the mine itself.
- **Silk Tunnel** (`silk_tunnel_skill.gd`): lays web traps across
  `tile_count = 4` tiles ahead of the caster, stopping early at a blocked
  tile.
- **Decoy** (`scenes/decoy.tscn`/`decoy.gd`): a `StaticBody2D` on
  `collision_layer = 4` (the enemy layer), spawned at
  `origin.global_position` — the caster's own tile. Player's
  `collision_mask` includes layer 4, so a spider dropping its own Decoy gets
  a solid obstacle spawned exactly on top of itself.
- The project has no shaders anywhere yet (`assets/` has no `.gdshader`
  files) — every entity's visuals are placeholder `_draw()` shapes.

## Design

### Shared outline shader

New `assets/shaders/outline.gdshader` (`shader_type canvas_item`), with
`uniform vec4 outline_color` and `uniform float outline_width` (in UV-texel
units). Standard alpha-edge-detection outline: for each fragment, if the
sprite's own alpha is below a threshold but an offset sample (4-direction)
is above it, output `outline_color`; otherwise sample normally. Applied via
a `ShaderMaterial` on a spider's `Sprite2D`.

New `components/outline_fx.gd` (`class_name OutlineFx extends RefCounted`,
static-only, mirrors `CombatFx`'s static-helper pattern already used for
flash/slash/shunt VFX):

```gdscript
static func set_outline(sprite: CanvasItem, enabled: bool, color: Color) -> void
```

Lazily creates and caches a `ShaderMaterial` (loading `outline.gdshader`) on
first use per sprite, toggling `enabled`/`color` on it — never replaces a
sprite's existing material wholesale, so this composes if a sprite later
needs another effect.

**Camouflage**: `CamouflageSkill._on_activate()` calls
`OutlineFx.set_outline(_visual, true, <camo outline color>)` alongside the
existing alpha fade; `break_camouflage()` calls
`OutlineFx.set_outline(_visual, false, ...)` alongside restoring alpha to
1.0. The alpha fade is unchanged — this adds the outline on top, it doesn't
replace anything already working.

**Sense**: `Player`'s existing `_on_effect_applied`/`_on_effect_expired`
handlers (which already relay `"sense"` to `Level.set_sense_active()`) are
the only ones that need to relay this — Sense is Player-only in practice
today, since `Enemy` has no `SenseSkill` component and never receives the
`"sense"` status tag. Both handlers additionally call a new
`Level.set_sense_outline(active: bool)` that iterates
`get_tree().get_nodes_in_group("spiders")` and
`get_tree().get_nodes_in_group("larvae")`, calling `OutlineFx.set_outline()`
on each one's `Sprite2D` (skipping any without one, e.g. placeholder
`_draw()`-only entities like `Decoy`/`TinySpiderling` — those already read
as visually distinct and don't need the treatment). This is a blanket
"everyone gets outlined while sense is active" rule, not a per-entity
occlusion raycast — consistent with how the existing occluder-disable is
already a blanket, not-per-entity effect.

### Hatchlings: escort AI + speed

`TinySpiderling` gains a two-state behavior:

- **Escort** (default): walks toward `_owner_spider.global_position +
  _escort_offset` (the same radial offset `HatchlingsSkill` used at spawn
  time, stored on `setup()`), keeping a loose ring around its owner. Falls
  back to `velocity = Vector2.ZERO` if `_owner_spider` is no longer valid.
- **Aggro**: breaks escort and chases/pecks exactly like today's logic once
  an enemy spider (any `"spiders"` node that isn't the owner) is within both
  line-of-sight and a new `aggro_radius: float = 180.0`. Reverts to escort
  once the target dies, leaves `aggro_radius`, or line-of-sight breaks.
- Line-of-sight uses the same `PhysicsRayQueryParameters2D`-against-world-layer
  pattern `Enemy._has_line_of_sight()` already uses — applies to both the
  aggro-trigger check and target acquisition, so a hatchling can no longer
  detect or chase through a wall.
- `move_speed` bumped from `90` to `180`.
- This entity is shared by Egg Mine's burst path today, but Egg Mine no
  longer uses `TinySpiderling` at all after this round (see below) — so the
  escort/aggro behavior only ever applies in the Hatchlings scouting context
  in practice, even though nothing hard-codes that assumption.

### Egg Mine redesign

`CocoonMine` changes from "spawns real attackers" to "hurts, then a cosmetic
flourish":

- **Direct burst damage**: on detonation, deals `burst_damage: float = 30.0`
  straight to the triggering body via its `Hurtbox`, before spawning the
  cosmetic burst.
- **Larvae immunity**: `_on_body_entered`'s trigger condition drops
  `body.is_in_group("larvae")` — only a `"spiders"` body (not the owner)
  triggers it now.
- **Cosmetic burst**: replaces the `TinySpiderling` burst with a new,
  self-contained `entities/skills/scenes/mine_spiderling.gd` (`Node2D`) —
  spawned at the same radial-offset pattern, waits `~0.3s`, deals one
  `cosmetic_damage: float = 1.0` tick to whatever's still within a small
  radius of it (via a direct `Hurtbox` lookup on nearby `"spiders"`/
  `"larvae"` groups, same pattern `TinySpiderling._attack()` already uses),
  then frees. No movement, no persistent AI, no chase.
- **Ceiling placement**: `EggMineSkill._on_activate()` reads the caster's
  current plane the same way `BlockadeSkill` already does
  (`source.get("_plane")` → `PlaneComponent.current_plane`) and passes it to
  `CocoonMine.arm()`. `_on_body_entered` only triggers for a body on the
  same plane the mine was armed on — mirrors the existing same-plane
  interaction rule `Level.is_blocked()`/`Blockade` already establish for the
  dual-plane design, no new mechanic invented.

### Silk Tunnel

`tile_count` default `4` → `6`. No other logic changes — the tile-by-tile
placement loop already stops early at a blocked tile.

### Decoy

`entities/skills/scenes/decoy.tscn`'s root `StaticBody2D` gets
`collision_layer = 0` (was `4`) — Decoy is no longer a physical obstacle to
anything, which removes the self-collision bug at its root (nothing to
collide with) rather than repositioning the spawn point. `Hurtbox`/
`HealthComponent`/group membership (`"spiders"`, `"decoys"`) are unchanged —
Decoy is still killable and still what `Enemy._acquire_target()`/melee
resolve against, per the already-working retargeting logic. The stale
"NOTE: joining spiders doesn't yet actually redirect Enemy's targeting"
comment in `decoy.gd` is corrected to reflect that it already does.

## Testing

- `tests/test_outline_fx.gd` (new): `set_outline(sprite, true, color)`
  attaches a `ShaderMaterial` with the given color/enabled state;
  `set_outline(sprite, false, ...)` disables it without erroring; calling it
  twice on the same sprite reuses/updates the cached material rather than
  stacking a new one each time.
- `tests/test_camouflage_wiring.gd` (extend): activating sets the outline
  material active on the sprite alongside the alpha fade; breaking clears
  both.
- New/extended `Level` test: `set_sense_outline(true)` sets the outline
  material on every spider/larva sprite in the tree; `false` clears them.
- `tests/test_tiny_spiderling.gd` (new): escorts toward
  `owner.global_position + offset` when no enemy is in range/LOS; switches
  to chase when an enemy enters both `aggro_radius` and LOS; reverts to
  escort once the target leaves LOS or `aggro_radius`; never chases through
  a wall (LOS-blocked enemy within raw distance is ignored);
  `move_speed == 180`.
- `tests/test_cocoon_mine.gd` (new/extend existing coverage): detonation
  deals `burst_damage` to the trigger's `Hurtbox`; a larva walking over an
  armed mine does not trigger it; a mine armed on the ceiling plane doesn't
  trigger for a ground-plane body and vice versa; the cosmetic burst spawns
  `mine_spiderling` instances (not `TinySpiderling`), each dealing
  `cosmetic_damage` once before freeing.
- `tests/test_silk_tunnel.gd` (extend if it exists, else check current
  coverage): tunnel length reflects `tile_count = 6`.
- `tests/test_decoy.gd` (extend): `collision_layer == 0` on the instantiated
  scene.
- Headless validation per the existing Godot workflow: import check, then a
  throwaway scene run (autoloads required for `Level`/`EventBus` paths).

## Out of scope

- Camouflage's attack-break wiring and Decoy's AI retargeting — both already
  built and tested (see Context).
- Per-entity occlusion raycasting for Sense's outline (blanket
  everyone-while-active is the chosen scope, not "only entities actually
  behind a wall from the player's viewpoint").
- Any change to `Hatchlings`' spawn count, lifetime, or `Egg Mine`'s
  placement input/trigger radius — only the items explicitly listed above.
- Real art/sprites for any of the placeholder-`_draw()` entities — the
  outline shader applies to whatever `Sprite2D` exists today (Player/Enemy),
  not a redesign of the placeholder visuals themselves.

# Class Identity Polish — Design

## Context

Raw playtest feedback flagged four small, independent class-identity gaps:
the spider never changes color per class, Weaver still suffers web
slowdowns like every other class, and Decoy's shot-speed multiplier is
dead data while its "costs more to fire" half was never built at all. This
is sub-project B of the larger feedback packet decomposition (see the
Net-caster rework spec/plan, already merged, for the full breakdown) — an
independent, small slice touching `SpiderClassData` and its four `.tres`
instances, `Player`, `Enemy`, `WebEmitter`, and `WebShot`.

## Current state

- `resources/spider_class_data.gd` (`SpiderClassData`) has no color field at
  all. `entities/player/player.tscn`'s `Sprite` uses one static texture
  regardless of active class; `Player._on_plane_changed()`
  (`entities/player/player.gd:263-264`) is the only place that ever sets
  `sprite.modulate`, hardcoding `Color(0.55, 0.65, 0.85, 0.85)` on the
  ceiling plane and `Color.WHITE` on the ground — there is no class-color
  concept to preserve today, but any fix must not have the ceiling tint and
  a new class tint overwrite each other. `Enemy`'s `Sprite`
  (`entities/enemy/enemy.tscn`, referenced as `facing_visual` in
  `entities/enemy/enemy.gd:65`) is likewise a single static texture,
  untouched by `_apply_class()` (`entities/enemy/enemy.gd:167-180`). Enemy
  has no plane/ceiling concept at all, so it has no equivalent conflict to
  design around.
- `Player.apply_web_hit()` (`entities/player/player.gd:363-371`) and
  `Enemy.apply_web_hit()` (`entities/enemy/enemy.gd:603-611`) are
  byte-identical: `if factor < 1.0: _mover.apply_slow(factor,
  slow_duration)`. The only two call sites that ever pass `factor < 1.0`
  are `WebTrap._entangle()` (`entities/web/web_trap.gd:71-75`,
  `web_slow_factor = 0.5`) and `WebShot._on_area_entered()`
  (`entities/web/web_shot.gd:63-72`, `slow_factor = 0.4`) — both are "web"
  effects, exactly what the feedback means by "any webs." Melee's own call
  (`Player._melee()`, `entities/player/player.gd:296`) passes `factor =
  1.0` (no slow), so it never reaches this branch regardless. `Blockade`
  (`entities/skills/scenes/blockade.gd`) is a hard `StaticBody2D` collider
  that stops movement via physics/`test_move`, entirely outside
  `apply_web_hit()` — it needs no special-casing to keep blocking Weavers.
  Both `Player`/`Enemy` already hold `_active_class_data: SpiderClassData`,
  readable for a class check (mirroring how `_web_enabled()` already reads
  `_active_class_data.web_enabled`, `entities/enemy/enemy.gd:359`).
- `SpiderClassData.web_projectile_speed_mult` (`resources/
  spider_class_data.gd`) is declared and authored per class (`decoy.tres`:
  `1.4`; `weaver.tres`: `0.8`; `wolf.tres`/`net_caster.tres`: `1.0`) but a
  repo-wide grep confirms it is read nowhere else — dead data.
  `WebEmitter.fire()` (`components/web_emitter.gd:29-40`) instantiates
  `web_shot_scene` and calls `shot.launch(dir, source)`; `WebShot.launch()`
  (`entities/web/web_shot.gd:35-39`) sets `_velocity = dir * speed` from
  its own fixed `@export var speed: float = 340.0` — no per-shooter
  scaling exists.
- No health-cost-to-fire mechanic exists anywhere. `WebEmitter.fire()`
  charges `hunger_cost` via `HungerComponent.charge_all()` — a flat,
  class-agnostic metabolic tax applied to every spider in the world, not a
  shooter-specific cost. `HealthComponent.take_damage(amount: float)`
  (`components/health_component.gd:21`) is the existing entry point for
  direct damage.
- `GameState.DEFAULT_MAX_HEALTH = 100.0` (`autoloads/game_state.gd:9`).

## Fix

### 1. Per-class spider color

Add to `resources/spider_class_data.gd`:

```gdscript
@export var display_color: Color = Color.WHITE
```

Set per `.tres` (tunable — adjust after playtesting):

- `resources/spiders/wolf.tres`: `display_color = Color(0.85, 0.4, 0.25)` (orange-red)
- `resources/spiders/weaver.tres`: `display_color = Color(0.4, 0.75, 0.45)` (green)
- `resources/spiders/decoy.tres`: `display_color = Color(0.65, 0.45, 0.85)` (purple)
- `resources/spiders/net_caster.tres`: `display_color = Color(0.85, 0.75, 0.35)` (gold)

`Player` stops letting `_on_plane_changed()` set `sprite.modulate` directly
from a hardcoded pair of colors. Instead, both `apply_class()` and
`_on_plane_changed()` route through one helper:

```gdscript
func _update_sprite_tint() -> void:
	var base := _active_class_data.display_color if _active_class_data != null else Color.WHITE
	if _plane.current_plane == Level.Layer.CEILING:
		sprite.modulate = base * Color(0.55, 0.65, 0.85, 0.85)
	else:
		sprite.modulate = base
```

`apply_class()` calls `_update_sprite_tint()` after setting
`_active_class_data`; `_on_plane_changed()` calls it instead of directly
assigning `sprite.modulate`. Multiplying the two colors together means a
class's identity color is still recognisable (dimmed/cooled) on the
ceiling rather than replaced by it — the two effects compose instead of
one clobbering the other.

`Enemy._apply_class()` gets one line: `facing_visual.modulate =
data.display_color` (no plane concept to compose with).

### 2. Weaver immune to web slowdown (not Blockade)

`Player` and `Enemy` each get a small helper (duplicated between them,
matching this codebase's established tolerance for small per-class
duplication like `_spawn_parent()`):

```gdscript
func _is_weaver() -> bool:
	return _active_class_data != null \
		and _active_class_data.spider_class == SpiderClassData.SpiderClass.WEAVER
```

`apply_web_hit()` in both files changes from:

```gdscript
	if factor < 1.0:
		_mover.apply_slow(factor, slow_duration)
```

to:

```gdscript
	if factor < 1.0 and not _is_weaver():
		_mover.apply_slow(factor, slow_duration)
```

Knockback and stun are untouched — only the slow itself is skipped. Since
melee's own `apply_web_hit` call already passes `factor = 1.0` (never
entering this branch) and Blockade never calls `apply_web_hit` at all, this
one-line-per-file change is the complete fix; nothing else needs touching
for the "except Blockade" clause.

### 3. Wire `web_projectile_speed_mult`

`components/web_emitter.gd`'s `fire()` gains an optional parameter:

```gdscript
func fire(from_position: Vector2, direction: Vector2, source: Node, speed_mult: float = 1.0) -> Node:
	...
	if shot.has_method("launch"):
		shot.launch(dir, source, speed_mult)
	...
```

`entities/web/web_shot.gd`'s `launch()` gains the same:

```gdscript
func launch(direction: Vector2, source: Node, speed_mult: float = 1.0) -> void:
	var dir := direction.normalized()
	_velocity = dir * speed * speed_mult
	_source = source
	rotation = dir.angle()
```

Both default to `1.0`, so every other caller (nothing else calls
`WebEmitter.fire()` or `WebShot.launch()` — confirmed by grep) is
unaffected by the signature change. `Player`'s and `Enemy`'s fire call
sites pass their active class's multiplier:

```gdscript
web_emitter.fire(global_position, facing, self,
	_active_class_data.web_projectile_speed_mult if _active_class_data != null else 1.0)
```

This is not Decoy-specific code — it's the generic class-multiplier
pattern `web_fire_rate_mult` already uses, so every class's existing
(mostly `1.0`) value becomes live, not just Decoy's `1.4`.

### 4. Decoy costs health to fire

Add to `resources/spider_class_data.gd`:

```gdscript
@export var web_fire_health_cost: float = 0.0
```

Only `resources/spiders/decoy.tres` sets a nonzero value: `web_fire_health_cost = 4.0` (4% of `GameState.DEFAULT_MAX_HEALTH` — tunable). Every
other class keeps the `0.0` default, authored or not.

`Player`'s and `Enemy`'s fire call sites, immediately after a successful
fire (the returned shot is non-null), apply the cost directly to the
shooter:

```gdscript
var shot := web_emitter.fire(global_position, facing, self, ...)
if shot != null and _active_class_data != null and _active_class_data.web_fire_health_cost > 0.0:
	health.take_damage(_active_class_data.web_fire_health_cost)
```

This is a shooter-specific direct-damage cost, distinct from
`WebEmitter.hunger_cost`'s existing flat, class-agnostic metabolic tax
applied to every spider in the world — the two costs are unrelated and
both apply.

## Out of scope for this slice

- Any other class's mechanics (Net-caster — already shipped; larvae —
  already shipped), skills bundle, UI/HUD, plane mechanics, environment
  tiles, centipedes.
- Swapping actual sprite textures per class — this uses `modulate` tinting
  on the existing single texture, matching the codebase's established
  placeholder-visual convention (no new art assets).

## Testing

- `tests/test_player_class_switching.gd` (already instantiates the real
  `Player` scene and calls `apply_class()`): new tests asserting
  `player.sprite.modulate` matches each class's `display_color` after
  `apply_class()`, and that toggling the ceiling plane multiplies the
  ceiling tint onto the current class color rather than replacing it
  (compare against the existing `_on_plane_changed` ceiling-tint constant).
- A parallel test file/section for `Enemy` (check `tests/
  test_enemy_class_kit.gd` for the established `_make_enemy()` +
  `_apply_class()` convention) asserting `facing_visual.modulate` matches
  each class's `display_color`.
- `Player`/`Enemy` `apply_web_hit()`: instantiate the real scene (matching
  `tests/test_distress_flash.gd`'s existing `_make_player()` +
  `player.apply_web_hit(Vector2i.ZERO, 0.5, 1.5, 0.0)` pattern), switch to
  Weaver, call `apply_web_hit()` with `factor < 1.0`, and assert
  `player._mover.speed_scale` stays `1.0` (no slow applied); switch to a
  non-Weaver class and assert the same call does change `speed_scale`;
  confirm knockback/stun still apply regardless of class by checking their
  own side effects (mover moved / `is_stunned()`) unchanged in both cases.
- `WebShot.launch()`: default `speed_mult = 1.0` leaves `_velocity`
  unchanged from today; a non-1.0 `speed_mult` scales `_velocity`
  proportionally. `WebEmitter.fire()`: passes through whatever
  `speed_mult` it's given to `launch()`; omitting the argument still
  works (defaults to `1.0`), so any existing call site that isn't updated
  keeps behaving exactly as before.
- Decoy health cost: firing while classed as Decoy reduces
  `health.current_health` by exactly `web_fire_health_cost`; firing as any
  other class leaves health untouched; a failed fire (e.g. on cooldown,
  `WebEmitter.fire()` returns `null`) costs no health.
- Manual verification in a running Godot session (headless boot/scene
  smoke test per the project's Godot validation workflow): cycle through
  all four classes and visually confirm each spider's distinct color,
  confirm the ceiling tint still reads as "on the ceiling" for whichever
  class is active, confirm a Weaver crossing a web doesn't slow down but
  still gets stopped by a Blockade, and confirm Decoy's shot is visibly
  faster and costs a sliver of health per shot.

# Grid, Melee, Webs & Dev Tools — Playtest Iteration 3

Date: 2026-07-09
Status: Implemented (inline) on `slice-1-rebuild`
Scope: Third playtest pass. Six requested areas, several of which turned out
to already be satisfied by iteration 2 (`2026-07-08-combat-and-webs-iteration.md`)
— those are called out below as verification-only.

## Process note

The six areas were investigated and implemented in the user's stated order,
each verified against a reproduction script or the GUT suite before moving to
the next, rather than written up as one combined design. This doc captures the
outcome and the judgment calls, matching the convention of the prior
iteration's spec.

## Changes

1. **Grid visualization + movement scaling.** `MazeRenderer` now draws thin
   grid lines over the floor tiles (always on — a permanent read on the
   tile-stepped movement, not a hidden dev toggle). Root-caused and fixed the
   "two-square jump": `Player._physics_process` called `GridMover.try_step`
   every physics frame a key was held, which kept `_buffered` "hot" with the
   held direction; because a step (0.12s) spans several physics frames, a tap
   that straddled a step boundary would auto-continue into a stale buffered
   step after release. Fix: `GridMover.cancel_buffer()`, called from Player
   whenever the resolved input direction is `Vector2i.ZERO` this frame.
   Confirmed via a headless repro: a ~0.15s hold dropped from 3 tiles to 2
   (proportional to hold duration, no phantom step); a single-frame tap stayed
   at 1 tile before and after.

2. **Larvae harvesting.** Already satisfied — verification only, no behaviour
   change. A larva has no Hitbox/Hurtbox at all, so there is structurally no
   damage path through collection; `WebTrap.try_consume` never touches health.
   Any spider (owner or not) can already consume a caught larva. Added
   `test_consuming_a_larva_never_damages_the_spider` to lock this in.

3. **Web collision rework.** Placed webs no longer physically block anyone.
   *Judgment:* rather than disable `WebTrap`'s collision shape (which would
   also blind web shots trying to destroy it), the player's and enemy's own
   collision masks had the trap layer bit removed (37→5, 35→3) — traps are now
   invisible to spider `test_move` blocking while remaining a valid physics
   target for web shots. This also fixes the self-trap bug: reproduced
   pre-fix (a spider standing on its own just-placed, now-armed trap became
   permanently stuck — Godot's `test_move` reports blocked when the body
   already overlaps a solid shape at the query position) and confirmed fixed.
   Removed the now-dead arm-delay/solid-body logic from `WebTrap` entirely.
   *Judgment call, flagged:* the request said "**all** spiders" get the 50%
   slow crossing a web, so the iteration-2 owner-immunity carve-out (placer
   immune until they'd stepped off) was removed — placing a trap on your own
   tile now slows you too. Slow factor changed 0.4 → 0.5 (literal "50%").
   Webs already dealt zero damage (unchanged, just re-verified).

4. **Melee combat.** Melee now also detects larvae in range and kills them
   outright (`web_kill()`, leaving a corpse) — *judgment:* mirrors how a web
   shot treats a larva (kill, not harvest); harvesting stays exclusive to the
   trap catch-and-consume flow, so there's still exactly one way to "eat."
   Melee now costs hunger to execute (`melee_hunger_cost` 5, via the existing
   `HungerComponent.charge_all`, whether or not the swing lands), and a
   placeholder slash-arc VFX (`CombatFx.spawn_slash`, a procedurally-drawn
   fading arc — no art asset yet) spawns at the impact tile on a landed hit.
   Symmetric on the enemy. **Max-hunger fail-safe:** `HungerComponent.charge_all`
   now checks each spider's own hunger before taxing it — a spider already at
   max hunger has the charge drained from health instead, so firing, laying a
   trap, or meleeing is never free just because you're starving. This applies
   uniformly to all three action types since they share `charge_all`.

5. **Entity collision.** Larvae walking onto/near a spider's tile now get a
   visual-only bump (`Larva._on_step_finished` → `CombatFx.shunt` on the
   larva's own sprite) — the mirror of the existing spider-steps-on-larva
   shunt; neither ever touches a grid position. Larva `step_time` raised
   0.14 → 0.34 (was actually *faster* than the enemy's 0.16 before this).
   **Spider overlap bug:** investigated via a 2000-frame fuzz repro (both
   spiders stepping toward each other every frame, worst-case contention) —
   found no overlap; the existing mask-based hard-block (from iteration 2)
   already holds. No fix applied since no bug was reproduced; added
   `test_spider_collision.gd` as a permanent regression guard instead of
   inventing a speculative change.

6. **Dev tools.** Three new bindings: `dev_reset_map` (R) frees and rebuilds
   the current level with a fresh random seed (reuses the existing
   descend/permadeath `_replace_level()` path), carrying the player's vitals
   forward. `dev_remove_wall` (X) carves the wall tile directly ahead of the
   player into floor (`Level.dev_remove_wall_at`: opens the `MazeData` cell,
   frees the tracked collision/occluder nodes, unsolids the AStar point,
   redraws). `dev_god_mode` (G) sets `GameState.god_mode`; *judgment:* scoped
   to the player only (checked via the "player" group, not "spiders"), so the
   enemy stays fully mortal — freezes incoming damage, passive hunger growth
   and starvation drain, and the metabolic action-cost charge for the player,
   leaving `satiate()` (eating) unaffected since that's a benefit, not a
   change to guard against.

## Playtest follow-up (same day)

Two more rounds of feedback after playtesting the above, plus a real bug
caught live via a screenshot and a temporary in-game diagnostic.

**Round 1:**
- Reset map (R) now clears carried vitals first — treated as a fresh spawn,
  not a carried-forward descent.
- Melee restructured: the slash VFX always plays on any swing (hit or whiff);
  hunger is only charged on a landed hit.
- `WebTrap._on_body_entered` skips `_entangle` when the spider is consuming a
  caught larva (eating is a reward, not a hazard) — an empty web still slows a
  crossing spider.
- Fixed a real bug: `Larva.set_caught()` snapped position but never stopped
  the in-flight `GridMover` step, so a larva caught mid-animation kept getting
  dragged toward its pre-capture destination on later frames. Added
  `GridMover.stop()`.
- Hardened the larva/spider "bump" check (both directions) from a 12px
  pixel-distance threshold to exact tile-coordinate comparison — the pixel
  threshold could plausibly miss from small position drift (e.g. after a
  knockback); no axis-specific bug was actually reproduced in testing, but the
  tile-exact version is strictly more correct regardless.
- Investigated the spider-overlap report at this point with combat/knockback
  fuzzing (3000 frames) and found nothing — see below for the real mechanism.

**Round 2:**
- Added pause (Esc): `get_tree().paused` toggle; `World` and `HUD` are
  `PROCESS_MODE_ALWAYS` so the toggle keeps working and a "PAUSED" label shows.
- Decoupled the distress flash entirely from `apply_web_hit` (which fired on
  every web-crossing slow, no damage involved) and hooked it to
  `HealthComponent.damaged` instead on both spiders — it now only fires on
  actual damage (melee, web shot, starvation), never a pure status effect.

**Spider overlap, root-caused:** two screenshots from a real playthrough
showed only one spider sprite where two should be — genuine same-tile overlap,
not adjacency. A temporary diagnostic (logged full state the instant tiles
coincided, plus breadcrumbs at `GridMover.knockback` and every landed melee
hit) caught it on the first live repro. Root cause: the enemy's own chase-step
was already in flight toward an empty tile when its melee landed on the player
and knocked them into that *same* tile — `GridMover`'s blocking check only
runs once, at the start of a step, so nothing re-validated the destination
when the enemy's already-committed step actually landed there. Earlier fuzzing
never caught this because it always had both spiders deciding simultaneously
from a stationary state, which correctly blocks; the real trigger needs one
spider already mid-step toward a tile plus something else (knockback) landing
the other spider there before that step finishes.

Fix: `GridMover.committed_tile()` (destination tile if mid-step, else current
tile) and `GridMover.spider_tile_contested()` (checks a prospective step
against every other spider's committed tile, not just live physical overlap).
Wired into both `Player._blocked` and a new `Enemy._blocked` (the enemy
previously had no `block_check` override at all, only the bare `test_move`
fallback). Confirmed with a regression test replicating the exact race
(`test_knockback_is_refused_into_a_tile_the_enemy_is_mid_step_toward`) and the
isolated unit-level case in `test_grid_mover.gd`.

## Round 3

Three more reports after the overlap fix: combat "not registering" on the
enemy, pause having no effect, and a request for a control/dev-tool overlay.

**Damage was a silent no-op on both spiders (root cause, not enemy-specific):**
`Hurtbox.health` was `@export var health: HealthComponent` — a Node-typed
export — but both `.tscn` files hand-wrote it as `health = NodePath(...)`.
Godot does not auto-resolve a NodePath value into a Node-typed export the way
the editor's own node-picker would serialize it; the field silently stayed
`null` on *both* Player and Enemy, so `receive_hit()`'s `if health != null`
guard skipped every melee and web-shot hit — no damage, no flash, and (for the
player's own attacks specifically) no knockback either, since without the
facing-aligned target actually landing, `apply_web_hit` was never called at
all. The enemy's attacks still visibly connected because its targeting always
computes the live distance to the player (never a stale cached direction),
so its knockback/stun landed — just silently without the (also-broken) damage
or flash. Fixed the same way `HungerComponent` already handles this exact
pattern: `@export var health_path: NodePath` resolved via `get_node_or_null`
in `_ready()`, with both `.tscn`s updated to the new property name. Regression
tests cover both the component in isolation and the two shipped scenes
directly, since the real bug was a property-name mismatch in the `.tscn`.

**Pause had no effect:** `World.process_mode = PROCESS_MODE_ALWAYS` (so its
own `_unhandled_input` could keep receiving the toggle) also meant `Level` —
a child of World with the default `PROCESS_MODE_INHERIT` — inherited ALWAYS
too, along with everything nested under it (Player, Enemy, Larvae). Pausing
the tree froze nothing. Fixed by explicitly setting `Level.process_mode =
PROCESS_MODE_PAUSABLE` right after instancing it in `World._build_level()`.

**Control/dev-tool indicator overlay:** new `ui/control_indicators.gd`
(`ControlIndicators`, a `CanvasLayer`), listing all 11 tracked actions/dev
toggles with a live label — held actions and persistent dev state (noclip,
freeze, god mode, pause) stay bright while their check is true; one-shot
actions (melee, place trap, toggle darkness, reset map, remove wall) flash
briefly the instant they fire. Built programmatically (no hand-authored
`.tscn` list) and set to `PROCESS_MODE_ALWAYS` so it (and the Paused row
specifically) keeps updating while the game itself is paused.

## New/changed shared pieces

- `GridMover.cancel_buffer()`, `GridMover.stop()`, `GridMover.committed_tile()`,
  `GridMover.spider_tile_contested()` (static).
- `MazeData.set_open(x, y)` — the one mutation point for the "remove wall" tool.
- `Level.dev_remove_wall_at(tile)`, `Level._wall_nodes` (tile → collision/occluder).
- `CombatFx.spawn_slash(holder, position, direction)` (`SlashVisual` inner class).
- `HungerComponent.charge_all` now takes a per-spider health/hunger fail-safe
  branch instead of a flat `add()` to everyone.
- `GameState.clear_carried_vitals()`; `HUD.set_paused_visible()`;
  `World._toggle_pause()`; `Enemy._blocked()` (new — it had none before).
- `Hurtbox.health_path` (replaces the non-functional `health` export).
- `ControlIndicators` (`ui/control_indicators.gd`/`.tscn`).
- `HealthComponent._is_player_owned()` / `HungerComponent._is_player_owned()`
  for god-mode's player scoping.
- `GameState.god_mode`.

## Tunable starting values

`melee_hunger_cost` 5.0, `web_slow_factor` 0.5, `larva step_time` 0.34,
slash VFX 0.18s fade. Feel out in playtest.

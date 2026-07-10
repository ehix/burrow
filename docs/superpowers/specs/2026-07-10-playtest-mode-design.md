# Playtest Mode

Date: 2026-07-10
Status: Approved, implementing directly (small, mirrors existing dev-tool
pattern one-for-one — see `2026-07-09-grid-melee-webs-devtools-iteration.md`
§6 for the precedent this extends).

## Problem

Playtesting a single new feature (e.g. the insect/item catch systems) today
means risking death or a forced fight with the enemy just to get into a
position to test. The existing dev tools (`freeze_others` / J, `god_mode` /
G) can approximate this but require two separate keypresses, and
`freeze_others` is too broad: it also halts larvae and all three hazards,
which is wrong here — catching insects/items should be tested under *live*
conditions (larvae still spawning and moving, hazards still firing on
schedule), not a frozen world.

## Decision

One new dev toggle, key `0`: `GameState.playtest_mode`.

**On:**
- `GameState.freeze_enemy = true` — a new, narrower flag than
  `freeze_others`. Gates only `Enemy._physics_process`'s AI decisions
  (movement, chasing, attacking, skill use). Larvae, hazards, and item
  pickups are untouched and keep behaving exactly as in live play.
- `GameState.god_mode = true` — already exists; makes the player immune to
  damage, starvation, and hunger growth (scoped to the player only, per its
  existing `_is_player_owned()` checks).

**Off:** both flags set back to `false`.

**Explicitly not suppressed:** enemy defeat and player death still trigger
`World._on_enemy_defeated` / `_on_player_died` exactly as in live play (depth
advance + level rebuild, or permadeath reset) — a demobilized enemy can still
be finished off by the player's own melee/web attacks (only its own AI is
frozen, not its ability to receive damage), so the "next depth" flow stays
testable without leaving Playtest Mode.

`freeze_others` (J) and `god_mode` (G) remain independently toggleable as
they are today — Playtest Mode is a convenience preset that sets two flags,
not a lock. A player can still hand-tune with J/G after enabling it.

## Scope

- `autoloads/game_state.gd`: new `freeze_enemy: bool` and `playtest_mode:
  bool` fields.
- `entities/enemy/enemy.gd`: `_physics_process`'s existing
  `if GameState.freeze_others: return` becomes
  `if GameState.freeze_others or GameState.freeze_enemy: return`.
- `world/world.gd`: new `_unhandled_input` branch toggling
  `GameState.playtest_mode` and driving `freeze_enemy`/`god_mode` from it.
- `project.godot`: new input action `dev_playtest_mode` bound to `0`.
- `ui/control_indicators.gd`: new "Playtest Mode (0)" held-indicator row.
- Tests: `GameState.playtest_mode` toggle behavior; `Enemy._physics_process`
  no-ops under `freeze_enemy`; `ControlIndicators` entry count bump.

## Out of scope

- The larva-spawn-timer gate gap noted in the prior iteration (new larvae
  aren't stopped by `freeze_others`) is **not** touched here — it's
  irrelevant to Playtest Mode (which doesn't set `freeze_others`) and touching
  it would be an unrelated fix outside this request.
- No changes to `HealthComponent` — the enemy's ability to *receive* damage
  stays live (see "explicitly not suppressed" above); only its own hunger and
  AI are paused.

## Follow-up (same day)

First playtest of the above surfaced a gap: `freeze_enemy` halted the
enemy's AI but not its `HungerComponent`, a sibling node ticking on its own
`_process` — so a frozen enemy's hunger kept rising (and could still starve
it to death, firing a live `enemy_defeated`) while "frozen." Fixed by scoping
`HungerComponent.tick()`/`add()` to `freeze_enemy` the same way they're
already scoped to `god_mode` for the player: a new `_is_enemy_owned()` check
(mirrors `_is_player_owned()`, keyed off the `"enemy"` group). Also closed a
second path to the same bug: `HungerComponent.charge_all`'s starving
fail-safe drains health directly rather than going through `add()`, so it
needed its own `freeze_enemy` exemption in the loop rather than inheriting
`add()`'s guard for free.

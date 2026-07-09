# Combat, Webs & Dev Tools — Playtest Iteration 2

Date: 2026-07-08
Status: Implemented (inline) on `slice-1-rebuild`
Scope: Second playtest pass, layered on the grid/web-combat redesign.

This captures nine changes the user asked for after playing the grid build, and
the judgment calls made where the request was ambiguous (the user asked to
proceed without questions and flag interpretations).

## Process note

These nine items are tightly coupled — knockback alone spans GridMover, the
hurtbox, and both spiders. That is exactly the "not independent, tightly
coupled" case the subagent-driven workflow routes away from, so this pass was
implemented inline (warm context, no per-task cold subagents) to respect the
active usage budget. The still-open plan Task 10 (web-shot redesign) was folded
into item 3/4 here rather than done separately then rewritten.

## Changes

1. **Enemy webs larvae again.** The enemy lays a web trap on its tile every
   `trap_interval` (5s) while SEEK_FOOD, in addition to contact-eating. A placed
   web's catch area was widened (radius 17 → 40) so a spider on an *adjacent*
   tile overlaps it and can consume — grid-snapped spiders never sat inside the
   old ring, which silently broke trap-eating. *Judgment:* consumption stays
   "any overlapping spider eats" (per the existing unit test); no owner-only
   auto-feed. The enemy gets fed because it lays traps along the larvae it is
   already pathing toward.

2. **Own-web immunity.** A placed web now slows any spider that crosses it
   (`web_slow_factor` 0.4 for 1.5s). The placer is immune until it has stepped
   off the web once (`body_exited` sets `_owner_left`). *Judgment:* "the effects
   of a web you laid" was read as this new cross-the-web slow, since placed webs
   previously had no status effect at all.

3. **Shots bump + impede.** A web-shot hurtbox hit now deals light damage (8),
   applies the slow, shoves the victim one tile along the shot's travel
   (`GridMover.knockback`), stuns it briefly (0.25s), and flashes it. *Judgment:*
   in a grid-locked game "bump back" = a forced one-tile grid step; "impede
   progress" = a short stun that blocks stepping. Knockback into a wall/spider
   is a no-op (still flashes/stuns).

4. **Spiders hard-block each other.** Player mask 33 → 37 and enemy mask 33 → 35
   add the other spider's layer, so `test_move` blocks a step into the other —
   they cannot pass, forcing combat. Walking over a larva gives a **visual-only**
   sprite shunt (`CombatFx.shunt`), never a body move (so it can't desync the
   grid); spiders still pass over larvae freely.

5. **Melee (F).** Strikes the spider one tile ahead: damage + shove + stun +
   flash, on a cooldown. Symmetric — the enemy melees the player at close range
   (inside `melee_range`) instead of firing.

6. **Distress flash.** `CombatFx.flash` pulses a sprite red then fades. Fired on
   any landed web/melee hit (`apply_web_hit`) and when a web catches a larva
   (`Larva.flash_distress`).

7. **Regular larva spawns, capped by map.** The Level spawns one larva every
   3.5s while under a cap of `open_tiles / 10`, clamped to [6, 18]. New larvae
   avoid tiles a spider is standing on.

8. **Web actions cost hunger (all spiders).** Firing (`hunger_cost` 4) and
   laying a trap (`hunger_cost` 6) raise *every* spider's hunger via
   `HungerComponent.charge_all`. The hard trap cap (`max_active`) was **removed**
   per "no hard limit on either" — hunger is now the only regulator.

9. **Dev tools.** `dev_noclip` (K) toggles `GameState.noclip` — the player walks
   through walls (its GridMover block seam bypasses `test_move`). `dev_freeze`
   (J) toggles `GameState.freeze_others` — the enemy and larvae stop; the player
   still moves. *Judgment:* freeze covers AI actors, not in-flight projectiles.

## New shared pieces

- `components/combat_fx.gd` (`CombatFx`) — stateless `flash()` / `shunt()`.
- `GridMover.knockback(dir)`, `stun(duration)`, `is_stunned()`.
- `HungerComponent.add(amount)`, `HungerComponent.charge_all(tree, amount)`.
- `Player.apply_web_hit` / `Enemy.apply_web_hit` (replaced `apply_web_slow`).

## Tunable starting values

All combat numbers are `@export`/`const` starting points: melee damage 12–14,
stun 0.25–0.3s, web slow 0.4×, web-trap slow 1.5s, larva cap divisor 10, spawn
interval 3.5s, fire/trap hunger cost 4/6. Feel out in playtest.

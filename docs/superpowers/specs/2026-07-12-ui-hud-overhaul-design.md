# UI/HUD Overhaul — Design

## Context

Playtest feedback asked for real player-facing UI covering four gaps: the
two class-specific skills have no on-screen indication of what they do or
when they're ready; permanent upgrades are only discoverable through the
dev-only debug overlay; the held item has only a barely-visible in-world
placeholder; and active status effects (Poison, Sense, buffs) have no
visibility at all. This is sub-project I of the larger feedback packet
decomposition (see the Item/Inventory Rework and Skill Fixes Bundle specs
for the prior pieces) — pulled forward ahead of its originally-planned
position (after F/G) because it directly helps playtesting now that D and E
have given it real data to display.

Two items from the roadmap's original description of this sub-project were
discovered, during design, to already be substantially covered by existing
infrastructure rather than needing new UI/UX decisions: `UpgradeCatalog`
already carries `display_name`/`description`/`rune_cost` for every upgrade,
and `StatusEffectComponent` already emits `EventBus.status_effect_applied`/
`status_effect_expired` — both just needed a listener, not new data.

Scope: `ui/hud.gd`/`.tscn`, three new UI scenes (`ui/skill_bar.*`,
`ui/shop_overlay.*`, `ui/status_effect_row.*`), `components/skill_component.gd`,
every class skill's `.tscn` node block, `entities/player/player.gd`,
`project.godot`, and their tests.

## Current state

- `ui/hud.gd`/`.tscn`: an existing `CanvasLayer` HUD — health/hunger bars
  (player + enemy), depth, win tally, runes, class labels, and toast/banner
  notifications (hazards, upgrades bought, round end). All driven by
  `EventBus` signals. Nothing here covers skills, items, or status effects.
- `ui/control_indicators.gd`/`.tscn`: a separate, explicitly dev/QA-only
  `CanvasLayer` listing every input action and dev toggle with a live
  active/idle indicator — stays untouched, out of scope (per your answer:
  build alongside, not replace).
- `components/skill_component.gd`: every skill (`HatchlingsSkill`,
  `CamouflageSkill`, etc.) already extends this for `cooldown`/`hunger_cost`/
  `activate()`/`can_activate()`. No `display_name`/`description` exports
  exist yet, and `_cooldown_left` (the value a HUD would need) is private
  with no public getter.
- `entities/player/player.gd`: `CLASS_SKILLS` already maps each
  `SpiderClassData.SpiderClass` id to its two class-specific skill action
  names (e.g. Wolf → `["hatchlings", "egg_mine"]`) — this is the existing
  seam a skill-bar would key off of. `apply_class()` already emits
  `EventBus.class_changed`.
- `resources/upgrade_catalog.gd`/`upgrade_registry.gd`: `UpgradeCatalog` has
  `display_name`, `description`, `rune_cost` fully authored for all 4
  upgrades already (`resources/upgrades/*.tres`) — currently only surfaced
  via `ControlIndicators`' dev-only key list.
- `components/status_effect_component.gd`: `apply()`/`_expire()` already
  emit `EventBus.status_effect_applied(who, id, magnitude, duration)` /
  `status_effect_expired(who, id)`. Five ids currently in use across the
  codebase: `sense`, `venomous`, `poison`, `silk_haste`, `seed_haste`.
- `entities/player/player.gd` (sub-project D): `Player.inventory` (an
  `InventoryComponent`) already exposes `held_item`/`item_held_changed`.
  `Player._draw()` already renders a placeholder colored dot for it, keyed
  by `ConsumableItem.ITEM_COLORS` — explicitly noted in that sub-project as
  a placeholder for this one to build real UI around.
- No shader/icon art exists for skills or items — every placeholder in this
  project so far is a colored shape (world-space `_draw()` calls for
  entities; this sub-project is the first to need Control-based colored
  placeholders, since it's screen-space UI, not world-space).
- Free, unbound keys remaining in `project.godot`'s `[input]` section after
  D and E: every letter and digit 0-4 are taken, along with Tab (D),
  Space/Enter/Escape. Digits 5-9 and most special keys remain free.

## Design

### Class skill buttons (2 slots, per-class swap)

`SkillComponent` gains two new exports, authored per skill instance in each
class's `.tscn` (same pattern `cooldown`/`hunger_cost` already use):

```gdscript
@export var display_name: String = ""
@export var description: String = ""
```

And a public getter alongside the existing private `_cooldown_left`:

```gdscript
func remaining_cooldown() -> float:
	return _cooldown_left
```

New `ui/skill_bar.gd`/`.tscn`: two icon slots (colored `ColorRect`/`Panel` +
keybind-letter `Label` overlay — the placeholder style, per your answer).
On `EventBus.class_changed`, looks up `Player.CLASS_SKILLS[spider_class]`'s
two action names, resolves each to its `SkillComponent` node on the current
player instance, and binds that skill's `display_name`/`description` to the
icon's tooltip/label. Every frame (`_process`), polls
`remaining_cooldown()` on both bound skills: `> 0` dims the icon
(`modulate` darkened) and shows the countdown as text; `<= 0` clears both.
Sense and Remove Walls (the two non-class-locked utilities) are explicitly
out of scope for these two slots — the roadmap's "two shared skill buttons"
matches the class-skill slot count exactly, not the full set of activatable
skills.

### Shop overlay

New `ui/shop_overlay.gd`/`.tscn`: a `Control` panel, hidden by default,
toggled by a new `toggle_shop` input action bound to **5** (the only
convenient unbound key left). Lists all 4 `UpgradeRegistry.ALL` entries —
`display_name`, `description`, `rune_cost`, each row dimmed
(`modulate`) if `GameState.runes < rune_cost`. Purely informational:
purchasing still happens via the existing `buy_upgrade_1..4` keys, which
work identically whether the panel is open or closed — no change to
`GameState.buy_upgrade()` or any purchase-input plumbing.

### Inventory icon

A new icon on the main HUD (same colored-square placeholder style, color
keyed by `ConsumableItem.ITEM_COLORS.get(item.item_id, ...)`, matching the
existing item-color convention from sub-project D), bound to
`Player.inventory.item_held_changed` — shows/hides and re-colors as the
signal fires. `Player._draw()`'s existing world-space dot is explicitly
kept, not removed (per your answer) — it's the only way to see what the
*enemy* is holding, since the HUD only has access to the player's own
`InventoryComponent`.

### Status-effect indicators (player + enemy)

New `ui/status_effect_row.gd`/`.tscn`: one reusable row of badges (colored
square + countdown `Label`, same visual language as the skill/inventory
icons), instanced twice by `hud.tscn` — once bound to the player, once to
the enemy (mirroring the existing health/hunger-bar pairing). Driven by
`EventBus.status_effect_applied`/`status_effect_expired`, filtered by
`who == the row's bound spider`. A new dictionary (matching the existing
`CLASS_DISPLAY_NAMES`/`HAZARD_DISPLAY_NAMES` pattern already in `hud.gd`)
maps the five known ids to a display name + color:

```gdscript
const STATUS_DISPLAY := {
	&"sense": {"name": "Sense", "color": Color(0.3, 0.75, 0.55)},
	&"venomous": {"name": "Venomous", "color": Color(0.55, 0.25, 0.65)},
	&"poison": {"name": "Poisoned", "color": Color(0.5, 0.8, 0.3)},
	&"silk_haste": {"name": "Silk Haste", "color": Color(0.6, 0.85, 1.0)},
	&"seed_haste": {"name": "Seed Haste", "color": Color(0.85, 0.7, 0.25)},
}
```

Countdown ticks down locally from the `duration` value captured at apply
time (matching how the existing toast/banner timers already work via
`create_tween()`) rather than polling `StatusEffectComponent.time_left()`
every frame — simpler, and consistent with existing HUD code style.

### Wiring

`ui/hud.gd`/`.tscn` instances all three new scenes and forwards the two
new signal sources (`item_held_changed`, `status_effect_applied`/`expired`)
it doesn't already listen to. `entities/player/player.gd` needs no new
public surface beyond what already exists (`CLASS_SKILLS`, `inventory`) —
the skill bar resolves `SkillComponent` nodes by name lookup
(`get_node_or_null(action_name_to_node_name)` or an equivalent small map),
same duck-typed style used throughout this codebase (e.g.
`WorldItemPickup._inventory_of()`).

## Testing

- `tests/test_skill_component.gd` (extend if it exists, else new):
  `remaining_cooldown()` reflects `_cooldown_left` correctly, ticking to
  zero after `cooldown` seconds via `activate()`.
- `tests/test_skill_bar.gd` (new): rebinds to the correct two skills on
  `class_changed`; icon dims while `remaining_cooldown() > 0`; clears at
  zero.
- `tests/test_shop_overlay.gd` (new): all 4 upgrades listed; a row dims
  when `GameState.runes < rune_cost`, un-dims once affordable.
- `tests/test_status_effect_row.gd` (new): a badge appears on
  `status_effect_applied` for the bound spider, is ignored for a
  differently-bound spider, and clears on `status_effect_expired` or after
  its `duration` elapses.
- HUD's existing inventory-icon wiring: extend `tests/test_hud.gd` (or
  add a focused new test) to confirm the icon updates on
  `item_held_changed` and matches `ConsumableItem.ITEM_COLORS`.
- Headless validation per the existing Godot workflow: import check, then a
  throwaway scene run (autoloads required for `EventBus`/`GameState`).
- Manual playtest for actual visual layout/spacing/overlap — no automated
  visual-regression tooling exists in this project; this is the same gap
  every prior placeholder-UI sub-project has had.

## Out of scope

- Sense and Remove Walls getting their own skill-bar icons (only the two
  class-specific slots, per the roadmap's "two shared skill buttons").
- Click-to-activate skill buttons or click-to-buy shop UI — both stay
  read-only displays; all activation/purchase remains keyboard-only,
  matching the rest of the game.
- Removing `Player._draw()`'s world-space item dot.
- Real icon/font art — placeholders only, matching every prior sub-project.
- Retiring or modifying `ControlIndicators` (the dev debug overlay).

# UI/HUD Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the player real HUD visibility into their two class skills (name/keybind/cooldown), the upgrade shop, their held item, and active status effects on both spiders — all read-only displays, no new input-driven interactions beyond one shop-toggle key.

**Architecture:** Three new self-contained `Control`-based scenes (`SkillBar`, `ShopOverlay`, `StatusEffectRow`) each own one concern and are instanced into the existing `ui/hud.tscn`/`hud.gd`, which already owns all cross-cutting EventBus wiring. `SkillComponent` gains display metadata + a public cooldown getter; `Player` gains a small lookup so the skill bar can resolve "my current class's two skills" without guessing node names from action strings. `World.gd` (which already owns the `hud` reference and is the single choke point where a new `Player`/`Enemy` pair is created each descent) gains one new binding call.

**Tech Stack:** Godot 4.7 (GDScript), GUT 9.4.0 (vendored at `addons/gut/`) for tests.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-12-ui-hud-overhaul-design.md` — read once for full context.
- Godot binary: `~/.local/bin/godot`. Run GUT via:
  `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=<file>.gd 2>&1` (read the full output, not `tail`; drop `-gselect=` for the whole suite).
- Import check after any `.tscn` edit: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
- New `.gd` files generate an untracked `.gd.uid` sidecar the first time Godot imports/runs them — after each task, run `git status` and stage any stray `.gd.uid` files. This project has had this gotcha slip through before.
- All three new UI pieces are **read-only displays** — no click-to-activate, no click-to-buy. Activation/purchase stays exactly as it is today (keyboard-only). The only new input is the `toggle_shop` action.
- The only unbound convenient key left is digit **5** (physical_keycode `53`) — every letter, digit 0-4, Tab, Space, Enter/Escape are already claimed.
- This slice touches: `components/skill_component.gd`, `entities/player/player.gd`, `entities/player/player.tscn`, `ui/skill_bar.gd`/`.tscn` (new), `ui/shop_overlay.gd`/`.tscn` (new), `ui/status_effect_row.gd`/`.tscn` (new), `ui/hud.gd`/`.tscn`, `world/world.gd`, `project.godot`, and their tests. No other system.
- `EventBus.status_effect_applied(who: Node, id: StringName, magnitude: float, duration: float)`, `EventBus.status_effect_expired(who: Node, id: StringName)`, `EventBus.class_changed(spider_class: int)`, `EventBus.runes_changed(total: int)` are existing, unmodified signals this plan consumes — exact signatures, do not alter.
- `EventBus` is a persistent autoload — any signal connection made on it from a scene that survives across a depth descent (the HUD does; `Player`/`Enemy` do not) must guard against reconnecting the same callback twice, or every descent leaks one more duplicate connection.

---

### Task 1: `SkillComponent` display metadata + cooldown getter

**Files:**
- Modify: `components/skill_component.gd`
- Test: `tests/test_skill_component.gd` (new)

**Interfaces:**
- Produces: `SkillComponent.display_name: String = ""`, `SkillComponent.description: String = ""` (both `@export`), `SkillComponent.remaining_cooldown() -> float`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_skill_component.gd`:

```gdscript
extends GutTest
## SkillComponent (UI/HUD overhaul): remaining_cooldown() exposes the
## private cooldown timer read-only, for a HUD to poll without needing
## write access to _cooldown_left. display_name/description are new
## per-instance metadata, authored the same way cooldown/hunger_cost
## already are.


func test_remaining_cooldown_is_zero_before_first_activation() -> void:
	var skill := SkillComponent.new()
	add_child_autofree(skill)
	assert_eq(skill.remaining_cooldown(), 0.0)


func test_remaining_cooldown_reflects_cooldown_after_activate() -> void:
	var skill := SkillComponent.new()
	skill.cooldown = 5.0
	add_child_autofree(skill)
	var caster := Node2D.new()
	add_child_autofree(caster)

	skill.activate(caster)

	assert_eq(skill.remaining_cooldown(), 5.0)


func test_remaining_cooldown_ticks_down_and_reaches_zero() -> void:
	var skill := SkillComponent.new()
	skill.cooldown = 1.0
	add_child_autofree(skill)
	var caster := Node2D.new()
	add_child_autofree(caster)
	skill.activate(caster)

	skill._process(0.6)
	assert_almost_eq(skill.remaining_cooldown(), 0.4, 0.001)
	skill._process(0.5)
	assert_eq(skill.remaining_cooldown(), 0.0)


func test_display_name_and_description_default_to_empty_string() -> void:
	var skill := SkillComponent.new()
	add_child_autofree(skill)
	assert_eq(skill.display_name, "")
	assert_eq(skill.description, "")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_skill_component.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function 'remaining_cooldown'`.

- [ ] **Step 3: Write the implementation**

In `components/skill_component.gd`, add after `@export var hunger_cost: float = 10.0`:

```gdscript
## Read-only HUD metadata (UI/HUD overhaul) — authored per skill instance in
## each class's .tscn, same pattern cooldown/hunger_cost already use.
@export var display_name: String = ""
@export var description: String = ""
```

Add after `can_activate()`:

```gdscript
## How many seconds remain before can_activate() returns true again — the
## seam a HUD polls instead of reaching into the private _cooldown_left.
func remaining_cooldown() -> float:
	return _cooldown_left
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_skill_component.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add components/skill_component.gd tests/test_skill_component.gd
git status # stage tests/test_skill_component.gd.uid if it appears
git commit -m "Add SkillComponent display metadata and remaining_cooldown()"
```

---

### Task 2: `Player.active_skills()` + author skill display text

**Files:**
- Modify: `entities/player/player.gd`
- Modify: `entities/player/player.tscn`
- Test: `tests/test_player_class_switching.gd`

**Interfaces:**
- Consumes: `SkillComponent.display_name`/`.description` (Task 1).
- Produces: `Player.active_skills() -> Dictionary` (action-name `String` → `SkillComponent`, in `CLASS_SKILLS` order — this is the exact interface `ui/skill_bar.gd` (Task 3) resolves through).

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_player_class_switching.gd` (after the existing tests, using the file's own `_make_player()` helper):

```gdscript
func test_active_skills_returns_the_current_classs_two_skills_in_order() -> void:
	var player := _make_player() # defaults to Wolf -> hatchlings, egg_mine

	var skills := player.active_skills()

	assert_eq(skills.keys(), ["hatchlings", "egg_mine"])
	assert_eq(skills["hatchlings"], player._hatchlings)
	assert_eq(skills["egg_mine"], player._egg_mine)


func test_active_skills_updates_after_switching_class() -> void:
	var player := _make_player()

	player.apply_class(SpiderClassData.SpiderClass.DECOY)
	var skills := player.active_skills()

	assert_eq(skills.keys(), ["camouflage", "decoy"])
	assert_eq(skills["camouflage"], player._camouflage)
	assert_eq(skills["decoy"], player._decoy)


func test_each_class_skill_has_display_name_and_description_authored() -> void:
	var player := _make_player()
	var all_skills := [
		player._net_hold, player._net_shot, player._hatchlings, player._egg_mine,
		player._blockade, player._silk_tunnel, player._camouflage, player._decoy,
	]
	for skill in all_skills:
		assert_ne(skill.display_name, "", "%s needs a display_name" % skill)
		assert_ne(skill.description, "", "%s needs a description" % skill)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_player_class_switching.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function 'active_skills'`; once that's added, the display_name test still fails since the `.tscn` has no authored text yet.

- [ ] **Step 3: Write the implementation**

In `entities/player/player.gd`, add a new var after `var _class_data_by_id: Dictionary = {}`:

```gdscript
## action name -> the matching SkillComponent instance, built once in
## _ready() — the lookup active_skills() resolves CLASS_SKILLS' action-name
## lists through, instead of guessing node names from action strings.
var _skill_by_action: Dictionary = {}
```

In `_ready()`, add right after the existing `_class_data_by_id = {...}` assignment block:

```gdscript
	_skill_by_action = {
		"net_hold": _net_hold, "net_shot": _net_shot,
		"hatchlings": _hatchlings, "egg_mine": _egg_mine,
		"blockade": _blockade, "silk_tunnel": _silk_tunnel,
		"camouflage": _camouflage, "decoy": _decoy,
	}
```

Add a new public method after `_is_active_skill()`:

```gdscript
## The current class's two class-specific SkillComponents, keyed by their
## input action name in CLASS_SKILLS order — the seam ui/skill_bar.gd binds
## its two icons through.
func active_skills() -> Dictionary:
	var actions: Array = CLASS_SKILLS.get(_active_class, [])
	var result: Dictionary = {}
	for action in actions:
		var skill: SkillComponent = _skill_by_action.get(action)
		if skill != null:
			result[action] = skill
	return result
```

In `entities/player/player.tscn`, add `display_name`/`description` to each of the 8 class-skill node blocks:

```
[node name="NetHoldSkill" type="Node" parent="."]
script = ExtResource("16_nethold")
display_name = "Net Hold"
description = "Hold to snare a spider caught in your net."

[node name="NetShotSkill" type="Node" parent="."]
script = ExtResource("17_netshot")
net_shot_scene = ExtResource("18_netshot")
cooldown = 0.0
hunger_cost = 0.0
display_name = "Net Shot"
description = "Fire your held net to trap a spider at range."

[node name="HatchlingsSkill" type="Node" parent="."]
script = ExtResource("19_hatch")
hatchling_scene = ExtResource("20_spiderling")
display_name = "Hatchlings"
description = "Summon scouting hatchlings that escort you and strike nearby threats."

[node name="EggMineSkill" type="Node" parent="."]
script = ExtResource("21_eggmine")
mine_scene = ExtResource("22_mine")
display_name = "Egg Mine"
description = "Plant a hidden mine that bursts for heavy damage."

[node name="BlockadeSkill" type="Node" parent="."]
script = ExtResource("23_blockadeskill")
blockade_scene = ExtResource("24_blockade")
display_name = "Blockade"
description = "Raise a barrier one tile ahead of you."

[node name="SilkTunnelSkill" type="Node" parent="."]
script = ExtResource("25_silk")
trap_scene = ExtResource("8_trap")
display_name = "Silk Tunnel"
description = "Lay a web tunnel ahead and speed yourself up."

[node name="DecoySkill" type="Node" parent="."]
script = ExtResource("26_decoyskill")
decoy_scene = ExtResource("27_decoy")
display_name = "Decoy"
description = "Drop a decoy to divert enemy attention."
```

And, separately in the file, `CamouflageSkill`'s existing block:

```
[node name="CamouflageSkill" type="Node" parent="."]
script = ExtResource("12_camo")
display_name = "Camouflage"
description = "Turn nearly invisible for a short time."
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_player_class_switching.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add entities/player/player.gd entities/player/player.tscn tests/test_player_class_switching.gd
git commit -m "Add Player.active_skills() and author skill display text"
```

---

### Task 3: `SkillBar` UI

**Files:**
- Create: `ui/skill_bar.gd`
- Create: `ui/skill_bar.tscn`
- Test: `tests/test_skill_bar.gd` (new)

**Interfaces:**
- Consumes: `Player.active_skills() -> Dictionary` (Task 2), `SkillComponent.display_name`/`.description`/`.remaining_cooldown()` (Tasks 1-2).
- Produces: `SkillBar.bind_player(player: Player) -> void`, `SkillBar.DIM_COLOR`/`.READY_COLOR` (`Color` consts).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_skill_bar.gd`:

```gdscript
extends GutTest
## SkillBar (UI/HUD overhaul): shows the current class's two skills, their
## keybind/name, and dims + counts down while on cooldown. Re-binds
## automatically when the player's class changes.

const SkillBarScene := preload("res://ui/skill_bar.tscn")
const PlayerScene := preload("res://entities/player/player.tscn")


func _make_bar() -> SkillBar:
	var bar: SkillBar = SkillBarScene.instantiate()
	add_child_autofree(bar)
	return bar


func _make_player() -> Player:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	return player


func test_binds_the_default_classs_two_skills() -> void:
	var bar := _make_bar()
	var player := _make_player() # defaults to Wolf -> hatchlings, egg_mine

	bar.bind_player(player)

	assert_eq(bar._name_label1.text, player._hatchlings.display_name)
	assert_eq(bar._name_label2.text, player._egg_mine.display_name)
	assert_eq(bar._key_label1.text, "Y")
	assert_eq(bar._key_label2.text, "U")


func test_rebinds_when_the_class_changes() -> void:
	var bar := _make_bar()
	var player := _make_player()
	bar.bind_player(player)

	player.apply_class(SpiderClassData.SpiderClass.DECOY)
	EventBus.class_changed.emit(SpiderClassData.SpiderClass.DECOY)

	assert_eq(bar._name_label1.text, player._camouflage.display_name)
	assert_eq(bar._name_label2.text, player._decoy.display_name)


func test_dims_and_counts_down_while_on_cooldown() -> void:
	var bar := _make_bar()
	var player := _make_player()
	bar.bind_player(player)
	player._hatchlings.cooldown = 5.0
	player._hatchlings.activate(player)

	bar._process(0.0)

	assert_eq(bar._panel1.modulate, SkillBar.DIM_COLOR)
	assert_eq(bar._cooldown_label1.text, "5.0")


func test_shows_ready_color_and_no_countdown_once_off_cooldown() -> void:
	var bar := _make_bar()
	var player := _make_player()
	bar.bind_player(player)

	bar._process(0.0)

	assert_eq(bar._panel1.modulate, SkillBar.READY_COLOR)
	assert_eq(bar._cooldown_label1.text, "")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_skill_bar.gd 2>&1`
Expected: FAIL — `Cannot find class "SkillBar"` / scene doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `ui/skill_bar.gd`:

```gdscript
class_name SkillBar
extends Control
## Two class-skill icons (UI/HUD overhaul): shows the current class's two
## skills' keybind, name, and cooldown countdown. Read-only display —
## activation stays keyboard-only. Re-binds to the new pair whenever the
## player's class changes.

const DIM_COLOR := Color(0.4, 0.4, 0.4, 1.0)
const READY_COLOR := Color(1.0, 1.0, 1.0, 1.0)

@onready var _panel1: Panel = $Slot1
@onready var _key_label1: Label = $Slot1/KeyLabel1
@onready var _name_label1: Label = $Slot1/NameLabel1
@onready var _cooldown_label1: Label = $Slot1/CooldownLabel1
@onready var _panel2: Panel = $Slot2
@onready var _key_label2: Label = $Slot2/KeyLabel2
@onready var _name_label2: Label = $Slot2/NameLabel2
@onready var _cooldown_label2: Label = $Slot2/CooldownLabel2

var _player: Player = null
var _skill1: SkillComponent = null
var _skill2: SkillComponent = null


## Bind to `player`'s current class's two skills, and stay in sync with
## future class changes. Safe to call again on a fresh Player instance
## (e.g. after a depth descent) — the EventBus connection only attaches once.
func bind_player(player: Player) -> void:
	_player = player
	if not EventBus.class_changed.is_connected(_on_class_changed):
		EventBus.class_changed.connect(_on_class_changed)
	_rebind()


func _on_class_changed(_spider_class: int) -> void:
	_rebind()


func _rebind() -> void:
	if _player == null:
		return
	var skills := _player.active_skills()
	var actions := skills.keys()
	var action1: String = actions[0] if actions.size() > 0 else ""
	var action2: String = actions[1] if actions.size() > 1 else ""
	_skill1 = skills.get(action1)
	_skill2 = skills.get(action2)
	_bind_slot(action1, _skill1, _key_label1, _name_label1)
	_bind_slot(action2, _skill2, _key_label2, _name_label2)


func _bind_slot(action: String, skill: SkillComponent, key_label: Label, name_label: Label) -> void:
	if skill == null:
		key_label.text = ""
		name_label.text = ""
		name_label.tooltip_text = ""
		return
	name_label.text = skill.display_name
	name_label.tooltip_text = skill.description
	var events := InputMap.action_get_events(action)
	key_label.text = events[0].as_text_key_label() if events.size() > 0 else ""


func _process(_delta: float) -> void:
	_update_cooldown(_skill1, _panel1, _cooldown_label1)
	_update_cooldown(_skill2, _panel2, _cooldown_label2)


func _update_cooldown(skill: SkillComponent, panel: Panel, cooldown_label: Label) -> void:
	if skill == null:
		return
	var remaining := skill.remaining_cooldown()
	if remaining > 0.0:
		panel.modulate = DIM_COLOR
		cooldown_label.text = "%.1f" % remaining
	else:
		panel.modulate = READY_COLOR
		cooldown_label.text = ""
```

Create `ui/skill_bar.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://ui/skill_bar.gd" id="1_skillbar"]

[node name="SkillBar" type="Control"]
offset_right = 280.0
offset_bottom = 64.0
script = ExtResource("1_skillbar")

[node name="Slot1" type="Panel" parent="."]
offset_right = 64.0
offset_bottom = 64.0

[node name="KeyLabel1" type="Label" parent="Slot1"]
offset_right = 64.0
offset_bottom = 20.0
horizontal_alignment = 1

[node name="NameLabel1" type="Label" parent="Slot1"]
offset_top = 20.0
offset_right = 64.0
offset_bottom = 44.0
horizontal_alignment = 1
autowrap_mode = 2

[node name="CooldownLabel1" type="Label" parent="Slot1"]
offset_top = 44.0
offset_right = 64.0
offset_bottom = 64.0
horizontal_alignment = 1

[node name="Slot2" type="Panel" parent="."]
offset_left = 76.0
offset_right = 140.0
offset_bottom = 64.0

[node name="KeyLabel2" type="Label" parent="Slot2"]
offset_right = 64.0
offset_bottom = 20.0
horizontal_alignment = 1

[node name="NameLabel2" type="Label" parent="Slot2"]
offset_top = 20.0
offset_right = 64.0
offset_bottom = 44.0
horizontal_alignment = 1
autowrap_mode = 2

[node name="CooldownLabel2" type="Label" parent="Slot2"]
offset_top = 44.0
offset_right = 64.0
offset_bottom = 64.0
horizontal_alignment = 1
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_skill_bar.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add ui/skill_bar.gd ui/skill_bar.tscn tests/test_skill_bar.gd
git status # stage stray .gd.uid/.tscn.uid files
git commit -m "Add SkillBar: read-only display of the current class's two skills"
```

---

### Task 4: `ShopOverlay` UI

**Files:**
- Create: `ui/shop_overlay.gd`
- Create: `ui/shop_overlay.tscn`
- Modify: `project.godot`
- Test: `tests/test_shop_overlay.gd` (new)

**Interfaces:**
- Consumes: `UpgradeCatalog.display_name`/`.description`/`.rune_cost`, `UpgradeRegistry.ALL` (existing, unmodified), `GameState.runes` (existing), `EventBus.runes_changed(total: int)` (existing).
- Produces: `ShopOverlay.toggle() -> void`, `ShopOverlay.refresh() -> void`, `ShopOverlay.AFFORDABLE_COLOR`/`.UNAFFORDABLE_COLOR` (`Color` consts).

- [ ] **Step 1: Add the input action**

In `project.godot`, add after the `use_item={...}` block (before `[layer_names]`):

```
toggle_shop={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":53,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

(physical_keycode `53` is digit 5 — the only convenient unbound key left.)

- [ ] **Step 2: Write the failing tests**

Create `tests/test_shop_overlay.gd`:

```gdscript
extends GutTest
## ShopOverlay (UI/HUD overhaul): lists every upgrade with cost/description,
## dimming rows the player can't yet afford. Purely informational — never
## spends runes itself, purchase stays on the existing buy_upgrade_1-4 keys.

const ShopOverlayScene := preload("res://ui/shop_overlay.tscn")


func after_each() -> void:
	GameState.runes = 0 # don't leak into other tests


func _make_shop() -> ShopOverlay:
	var shop: ShopOverlay = ShopOverlayScene.instantiate()
	add_child_autofree(shop)
	return shop


func test_hidden_by_default() -> void:
	var shop := _make_shop()
	assert_false(shop.visible)


func test_toggle_flips_visibility() -> void:
	var shop := _make_shop()
	shop.toggle()
	assert_true(shop.visible)
	shop.toggle()
	assert_false(shop.visible)


func test_lists_every_upgrade_with_name_and_cost() -> void:
	var shop := _make_shop()
	assert_eq(shop._row_labels.size(), UpgradeRegistry.ALL.size())
	var first := UpgradeRegistry.ALL[0]
	assert_true(shop._row_labels[0].text.contains(first.display_name))
	assert_true(shop._row_labels[0].text.contains(str(first.rune_cost)))


func test_dims_a_row_the_player_cannot_afford() -> void:
	var shop := _make_shop()
	GameState.runes = 0

	shop.refresh()

	assert_eq(shop._row_labels[0].modulate, ShopOverlay.UNAFFORDABLE_COLOR)


func test_undims_a_row_once_affordable() -> void:
	var shop := _make_shop()
	var first := UpgradeRegistry.ALL[0]
	GameState.runes = first.rune_cost

	shop.refresh()

	assert_eq(shop._row_labels[0].modulate, ShopOverlay.AFFORDABLE_COLOR)


func test_refreshes_automatically_when_runes_change() -> void:
	var shop := _make_shop()
	var first := UpgradeRegistry.ALL[0]

	EventBus.runes_changed.emit(first.rune_cost)

	assert_eq(shop._row_labels[0].modulate, ShopOverlay.AFFORDABLE_COLOR)
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_shop_overlay.gd 2>&1`
Expected: FAIL — `Cannot find class "ShopOverlay"` / scene doesn't exist.

- [ ] **Step 4: Write the implementation**

Create `ui/shop_overlay.gd`:

```gdscript
class_name ShopOverlay
extends Control
## Informational upgrade-shop panel (UI/HUD overhaul), toggled by the
## "toggle_shop" action. Lists every UpgradeRegistry entry with its cost,
## dimming rows the player can't yet afford. Purchase still happens via the
## existing buy_upgrade_1..4 keys — this panel never spends runes itself.

const AFFORDABLE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const UNAFFORDABLE_COLOR := Color(0.5, 0.5, 0.5, 1.0)

@onready var _rows: VBoxContainer = $Rows

var _row_labels: Array[Label] = []


func _ready() -> void:
	visible = false
	for upgrade in UpgradeRegistry.ALL:
		var label := Label.new()
		_rows.add_child(label)
		_row_labels.append(label)
	EventBus.runes_changed.connect(func(_total: int) -> void: refresh())
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_shop"):
		toggle()


func toggle() -> void:
	visible = not visible


func refresh() -> void:
	for i in UpgradeRegistry.ALL.size():
		var upgrade := UpgradeRegistry.ALL[i]
		var label := _row_labels[i]
		label.text = "%s — %dr: %s" % [upgrade.display_name, upgrade.rune_cost, upgrade.description]
		label.modulate = AFFORDABLE_COLOR if GameState.runes >= upgrade.rune_cost else UNAFFORDABLE_COLOR
```

Create `ui/shop_overlay.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://ui/shop_overlay.gd" id="1_shop"]

[node name="ShopOverlay" type="Control"]
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -220.0
offset_top = -110.0
offset_right = 220.0
offset_bottom = 110.0
script = ExtResource("1_shop")

[node name="Background" type="Panel" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Rows" type="VBoxContainer" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 12.0
offset_top = 12.0
offset_right = -12.0
offset_bottom = -12.0
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_shop_overlay.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 6: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add project.godot ui/shop_overlay.gd ui/shop_overlay.tscn tests/test_shop_overlay.gd
git status # stage stray .gd.uid/.tscn.uid files
git commit -m "Add ShopOverlay: informational upgrade list toggled by 5"
```

---

### Task 5: `StatusEffectRow` UI

**Files:**
- Create: `ui/status_effect_row.gd`
- Create: `ui/status_effect_row.tscn`
- Test: `tests/test_status_effect_row.gd` (new)

**Interfaces:**
- Consumes: `EventBus.status_effect_applied(who: Node, id: StringName, magnitude: float, duration: float)`, `EventBus.status_effect_expired(who: Node, id: StringName)` (existing, unmodified).
- Produces: `StatusEffectRow.bind_spider(spider: Node) -> void`, `StatusEffectRow.STATUS_DISPLAY: Dictionary`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_status_effect_row.gd`:

```gdscript
extends GutTest
## StatusEffectRow (UI/HUD overhaul): one badge per active status-effect id
## for whichever spider this row is bound to, ignoring effects on any other
## spider. Countdown ticks locally toward zero; removal happens on
## EventBus.status_effect_expired.

const StatusEffectRowScene := preload("res://ui/status_effect_row.tscn")


func _make_row() -> StatusEffectRow:
	var row: StatusEffectRow = StatusEffectRowScene.instantiate()
	add_child_autofree(row)
	return row


func _make_spider() -> Node2D:
	var spider := Node2D.new()
	add_child_autofree(spider)
	return spider


func test_shows_a_badge_when_its_bound_spider_gets_a_status_effect() -> void:
	var row := _make_row()
	var spider := _make_spider()
	row.bind_spider(spider)

	row._on_status_effect_applied(spider, &"poison", 2.0, 3.0)

	assert_true(row._badges.has(&"poison"))
	assert_eq(row._badges[&"poison"].text, "Poisoned 3")


func test_ignores_a_status_effect_on_a_different_spider() -> void:
	var row := _make_row()
	var spider := _make_spider()
	var other := _make_spider()
	row.bind_spider(spider)

	row._on_status_effect_applied(other, &"poison", 2.0, 3.0)

	assert_false(row._badges.has(&"poison"))


func test_badge_counts_down_over_time() -> void:
	var row := _make_row()
	var spider := _make_spider()
	row.bind_spider(spider)
	row._on_status_effect_applied(spider, &"sense", 1.0, 5.0)

	row._process(2.0)

	assert_eq(row._badges[&"sense"].text, "Sense 3")


func test_badge_removed_on_status_effect_expired() -> void:
	var row := _make_row()
	var spider := _make_spider()
	row.bind_spider(spider)
	row._on_status_effect_applied(spider, &"sense", 1.0, 5.0)

	row._on_status_effect_expired(spider, &"sense")

	assert_false(row._badges.has(&"sense"))


func test_unknown_status_id_falls_back_to_its_raw_name() -> void:
	var row := _make_row()
	var spider := _make_spider()
	row.bind_spider(spider)

	row._on_status_effect_applied(spider, &"mystery_buff", 1.0, 4.0)

	assert_eq(row._badges[&"mystery_buff"].text, "mystery_buff 4")


func test_real_event_bus_emission_reaches_the_bound_spider() -> void:
	var row := _make_row()
	var spider := _make_spider()
	row.bind_spider(spider)

	EventBus.status_effect_applied.emit(spider, &"poison", 2.0, 3.0)

	assert_true(row._badges.has(&"poison"))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_status_effect_row.gd 2>&1`
Expected: FAIL — `Cannot find class "StatusEffectRow"` / scene doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `ui/status_effect_row.gd`:

```gdscript
class_name StatusEffectRow
extends Control
## One spider's active-status-effect badges (UI/HUD overhaul) — one badge
## per active EventBus.status_effect_applied id, showing a color + a local
## countdown that ticks toward zero, removed on
## EventBus.status_effect_expired. Filtered to whichever spider this row is
## bound to via bind_spider().

const STATUS_DISPLAY := {
	&"sense": {"name": "Sense", "color": Color(0.3, 0.75, 0.55)},
	&"venomous": {"name": "Venomous", "color": Color(0.55, 0.25, 0.65)},
	&"poison": {"name": "Poisoned", "color": Color(0.5, 0.8, 0.3)},
	&"silk_haste": {"name": "Silk Haste", "color": Color(0.6, 0.85, 1.0)},
	&"seed_haste": {"name": "Seed Haste", "color": Color(0.85, 0.7, 0.25)},
}

@onready var _row: HBoxContainer = $Row

var _bound_spider: Node = null
var _badges: Dictionary = {}    # StringName -> Label
var _time_left: Dictionary = {} # StringName -> float


## Bind to `spider`. Safe to call again on a fresh spider instance (e.g.
## after a depth descent) — the EventBus connections only attach once.
func bind_spider(spider: Node) -> void:
	_bound_spider = spider
	if not EventBus.status_effect_applied.is_connected(_on_status_effect_applied):
		EventBus.status_effect_applied.connect(_on_status_effect_applied)
	if not EventBus.status_effect_expired.is_connected(_on_status_effect_expired):
		EventBus.status_effect_expired.connect(_on_status_effect_expired)


func _process(delta: float) -> void:
	for id in _time_left.keys().duplicate():
		_time_left[id] = maxf(0.0, _time_left[id] - delta)
		_update_label(id)


func _on_status_effect_applied(who: Node, id: StringName, _magnitude: float, duration: float) -> void:
	if who != _bound_spider:
		return
	_time_left[id] = duration
	if not _badges.has(id):
		var label := Label.new()
		_row.add_child(label)
		_badges[id] = label
	var display: Dictionary = STATUS_DISPLAY.get(id, {"name": str(id), "color": Color.WHITE})
	_badges[id].modulate = display["color"]
	_update_label(id)


func _on_status_effect_expired(who: Node, id: StringName) -> void:
	if who != _bound_spider:
		return
	_remove_badge(id)


func _update_label(id: StringName) -> void:
	var display: Dictionary = STATUS_DISPLAY.get(id, {"name": str(id), "color": Color.WHITE})
	var label: Label = _badges.get(id)
	if label != null:
		label.text = "%s %.0f" % [display["name"], _time_left.get(id, 0.0)]


func _remove_badge(id: StringName) -> void:
	var label: Label = _badges.get(id)
	if label != null and is_instance_valid(label):
		label.queue_free()
	_badges.erase(id)
	_time_left.erase(id)
```

Create `ui/status_effect_row.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://ui/status_effect_row.gd" id="1_row"]

[node name="StatusEffectRow" type="Control"]
offset_right = 300.0
offset_bottom = 24.0
script = ExtResource("1_row")

[node name="Row" type="HBoxContainer" parent="."]
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_status_effect_row.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add ui/status_effect_row.gd ui/status_effect_row.tscn tests/test_status_effect_row.gd
git status # stage stray .gd.uid/.tscn.uid files
git commit -m "Add StatusEffectRow: per-spider active status-effect badges"
```

---

### Task 6: Wire everything into the HUD

**Files:**
- Modify: `ui/hud.gd`
- Modify: `ui/hud.tscn`
- Modify: `world/world.gd`
- Test: `tests/test_hud.gd`

**Interfaces:**
- Consumes: `SkillBar.bind_player()` (Task 3), `ShopOverlay` (Task 4, no direct call needed — self-contained), `StatusEffectRow.bind_spider()` (Task 5), `Player.inventory.held_item`/`.item_held_changed` (existing, from sub-project D), `ConsumableItem.ITEM_COLORS` (existing, from sub-project D), `Level.enemy: Node2D` (existing, public).
- Produces: `HUD.bind_spiders(player: Player, enemy: Node2D) -> void` — the one new seam `World.gd` calls each time a new `Player`/`Enemy` pair is built.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_hud.gd` (after the existing tests, using the file's own `_make_hud()` helper):

```gdscript
func test_bind_spiders_wires_the_skill_bar_and_status_rows() -> void:
	var hud := _make_hud()
	var player: Player = preload("res://entities/player/player.tscn").instantiate()
	add_child_autofree(player)
	var enemy := _make_spider("enemy")

	hud.bind_spiders(player, enemy)

	assert_eq(hud.skill_bar._name_label1.text, player._hatchlings.display_name)
	assert_not_null(hud.player_status_row._bound_spider)
	assert_eq(hud.enemy_status_row._bound_spider, enemy)


func test_bind_spiders_primes_the_inventory_icon_from_the_players_current_item() -> void:
	var hud := _make_hud()
	var player: Player = preload("res://entities/player/player.tscn").instantiate()
	add_child_autofree(player)
	var item := FungusSenseItem.new()
	player.inventory.held_item = item

	hud.bind_spiders(player, _make_spider("enemy"))

	assert_true(hud.inventory_icon.visible)
	assert_eq(hud.inventory_icon.modulate, ConsumableItem.ITEM_COLORS.get(item.item_id, Color.WHITE))


func test_inventory_icon_hides_when_the_held_item_clears() -> void:
	var hud := _make_hud()
	var player: Player = preload("res://entities/player/player.tscn").instantiate()
	add_child_autofree(player)
	hud.bind_spiders(player, _make_spider("enemy"))
	player.inventory.held_item = FungusSenseItem.new()
	player.inventory.item_held_changed.emit(player.inventory.held_item)
	assert_true(hud.inventory_icon.visible)

	player.inventory.held_item = null
	player.inventory.item_held_changed.emit(null)

	assert_false(hud.inventory_icon.visible)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_hud.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function 'bind_spiders'`.

- [ ] **Step 3: Write the implementation**

In `ui/hud.tscn`, add ext_resources after the existing `id="1_hud"` line:

```
[ext_resource type="PackedScene" path="res://ui/skill_bar.tscn" id="2_skillbar"]
[ext_resource type="PackedScene" path="res://ui/shop_overlay.tscn" id="3_shop"]
[ext_resource type="PackedScene" path="res://ui/status_effect_row.tscn" id="4_statusrow"]
```

Change `load_steps=2` (line 1) to `load_steps=5`.

Add these node blocks at the end of the file (after the existing `RoundBannerLabel` block):

```
[node name="SkillBar" parent="Root" instance=ExtResource("2_skillbar")]
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -140.0
offset_top = -90.0
offset_right = 140.0
offset_bottom = -16.0

[node name="ShopOverlay" parent="Root" instance=ExtResource("3_shop")]

[node name="InventoryIcon" type="Panel" parent="Root"]
visible = false
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 16.0
offset_top = -80.0
offset_right = 80.0
offset_bottom = -16.0

[node name="PlayerStatusRow" parent="Root" instance=ExtResource("4_statusrow")]
offset_left = 16.0
offset_top = 220.0
offset_right = 316.0
offset_bottom = 244.0

[node name="EnemyStatusRow" parent="Root" instance=ExtResource("4_statusrow")]
offset_left = 260.0
offset_top = 220.0
offset_right = 560.0
offset_bottom = 244.0
```

In `ui/hud.gd`, add new `@onready` vars after the existing `@onready var hazard_toast_label`:

```gdscript
@onready var skill_bar: SkillBar = $Root/SkillBar
@onready var shop_overlay: ShopOverlay = $Root/ShopOverlay
@onready var inventory_icon: Panel = $Root/InventoryIcon
@onready var player_status_row: StatusEffectRow = $Root/PlayerStatusRow
@onready var enemy_status_row: StatusEffectRow = $Root/EnemyStatusRow
```

Add a new public method, anywhere after `_ready()`:

```gdscript
## Called by World each time a new Player/Enemy pair is built (initial spawn
## and every depth descent) — the one seam this HUD needs to (re)bind its
## per-spider pieces through. `enemy` may be null (defensive; Level always
## builds one in practice).
func bind_spiders(player: Player, enemy: Node2D) -> void:
	if player != null:
		skill_bar.bind_player(player)
		player_status_row.bind_spider(player)
		if not player.inventory.item_held_changed.is_connected(_on_item_held_changed):
			player.inventory.item_held_changed.connect(_on_item_held_changed)
		_on_item_held_changed(player.inventory.held_item)
	if enemy != null:
		enemy_status_row.bind_spider(enemy)


func _on_item_held_changed(item: ConsumableItem) -> void:
	inventory_icon.visible = item != null
	if item != null:
		inventory_icon.modulate = ConsumableItem.ITEM_COLORS.get(item.item_id, Color.WHITE)
```

In `world/world.gd`, change `_build_level()` to call the new binding after the level is built:

```gdscript
func _build_level() -> void:
	_level = LevelScene.instantiate()
	# World is PROCESS_MODE_ALWAYS so its own input keeps working while paused;
	# without this explicit override Level would inherit ALWAYS from World too
	# and pausing would freeze nothing at all.
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_level)
	_level.build()
	_snap_camera()
	_bind_hud()
	_rebuilding = false
```

Add a new private method, near `_snap_camera()`:

```gdscript
## Hands the freshly-built Level's Player/Enemy to the HUD (skill bar,
## status-effect rows, inventory icon) — called once per _build_level(), so
## every depth descent re-binds to the new instances the same way the
## camera already re-snaps to them.
func _bind_hud() -> void:
	if hud == null or not hud.has_method("bind_spiders"):
		return
	var player := _current_player() as Player
	var level := _level as Level
	var enemy: Node2D = level.enemy if level != null else null
	hud.bind_spiders(player, enemy)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_hud.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Run the full suite**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1`
Expected: `All tests passed!` (there's a known pre-existing intermittent flake in `test_larva_hazards.gd::test_open_ground_does_not_block_a_spawned_larva`, unrelated to this branch — if only that one fails, re-run once to confirm it's the same pre-existing flake before treating it as a pass).

- [ ] **Step 7: Manual boot smoke check**

Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"`
Expected: no new errors (the HUD now instances 3 more scenes and World calls `_bind_hud()` on every build — this exercises that path headlessly, though the actual on-screen result still needs a manual windowed check per the design's testing section).

- [ ] **Step 8: Commit**

```bash
git add ui/hud.gd ui/hud.tscn world/world.gd tests/test_hud.gd
git commit -m "Wire SkillBar, ShopOverlay, StatusEffectRow, and inventory icon into HUD"
```

---

### Final check

- [ ] Run the full suite once more end-to-end: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1` — expect `All tests passed!`.
- [ ] Run `git status` — stage any stray `.gd.uid`/`.tscn.uid` sidecars from new files before opening the PR.
- [ ] Manual playtest pass (headless tests verify wiring/state, not the rendered result): boot the game windowed, confirm the skill bar shows the right two skills/keybinds for the starting class and updates on class-cycle (Q); use a skill and watch it dim + count down; press 5 and confirm the shop panel appears with all 4 upgrades, dimmed ones you can't afford; pick up an item and confirm the HUD inventory icon appears/colors correctly, then use it and confirm it disappears; get poisoned/sensed/hasted and confirm a status badge appears with a countdown and clears on expiry, for both the player and the enemy; confirm nothing overlaps the existing health/hunger/depth/wins/runes/class labels or the dev ControlIndicators list.

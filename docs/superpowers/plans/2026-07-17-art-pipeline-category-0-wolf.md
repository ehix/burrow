# Category 0 — Art Pipeline Proof-of-Concept (Wolf) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take Wolf through the full SpriteCook art pipeline (still → directional animation frames → Godot `AnimatedSprite2D`) end-to-end for **both** the ground and ceiling plane, replacing `Player`'s static `Sprite2D` and its rotation-based facing with a real animated, non-rotating, directional, plane-aware sprite — proving the pipeline before any other category starts, and closing the underside/ceiling sprite gap left deferred since `docs/superpowers/specs/2026-07-14-tunnel-visual-rework-design.md`.

**Architecture:** SpriteCook's guided `generate_character`/`generate_character_animations` topdown workflow produces two independent base characters (ground-facing, underside/ventral) each with 9 named animations (3 directions × idle/walk, plus 3 single-pose combat states). `export_godot_character_package` materializes each as its own Godot `SpriteFrames` resource. `Player` swaps its `Sprite2D` for `AnimatedSprite2D`, replaces `sprite.rotation = facing.angle()` with a pure facing→animation-name lookup (no rotation, matching the Phase 2 faux-3D wall renderer's fixed-orientation convention), wires that lookup plus the three combat states to existing gameplay signals, and swaps which `SpriteFrames` resource is active whenever `PlaneComponent.plane_changed` fires.

**Tech Stack:** Godot 4.7 (GDScript), SpriteCook MCP tools, no GUT (not installed in this project — verification is headless Godot checks + a real windowed screenshot, per this project's established convention).

## Global Constraints

- SpriteCook only — no Comfy Cloud, per `docs/superpowers/specs/2026-07-17-art-pipeline-design.md` §4.
- Pixel art only (`pixel=true` / SpriteCook's guided pixel-art character workflow), per spec §2/§5.
- No sprite rotation in code — directional animation selection instead, per spec §5.
- `idle`/`walk` get full directional coverage (front/back/right, mirrored to left); `attack`/`hurt`/`death` stay single front-facing pose, mirrored left/right only, per spec §5.
- Every creature with a `PlaneComponent` gets a **full second animation set** for the underside/ceiling view (same 9 states as ground), swapped in on `PlaneComponent.plane_changed`, per spec §5 — this closes the Phase 2 tunnel-rework spec's deferred underside-sprite requirement for real.
- Check `get_credit_balance` before spending and again after Category 0 completes — record the real cost against the ~500-credit estimate (spec §4/§9).
- Every generated asset needs the user's visual sign-off (manifest `status: approved`) before being treated as final, per spec §9.
- Verify with a real windowed Godot screenshot on **both** planes, not just headless/automated checks, per spec §9 — this project has repeatedly found visual bugs invisible to automated checks alone.
- Godot validation commands (`~/.local/bin/godot`, `GALLIUM_DRIVER=d3d12` for windowed runs) and scratch-file hygiene (delete throwaway `.gd`/`.tscn`/`.gd.uid` files before committing, never leave them in `git status`) follow this project's established conventions.

---

### Task 1: Confirm SpriteCook subscription is active

**Files:** None (tool calls only).

**Interfaces:**
- Produces: `starting_balance` (integer, recorded in this task's output for Task 10 to diff against).

- [ ] **Step 1: Check the current credit balance**

Call `mcp__plugin_spritecook_spritecook__get_credit_balance` with no arguments.

- [ ] **Step 2: Verify a subscription is active**

Expected: `total_credits > 0` (the design spec recorded 0 credits, free tier, on 2026-07-17, pre-subscription — this task exists specifically to confirm the 800-credit/month subscription mentioned in spec §4 is now active). If `total_credits == 0`, stop here and tell the user the subscription doesn't appear active yet rather than proceeding to spend against a zero balance.

- [ ] **Step 3: Record the starting balance**

Write the returned `total_credits` value down (in your task notes, not a file) as `starting_balance` — Task 10 needs it to compute actual spend.

---

### Task 2: Generate Wolf's ground-facing base character

**Files:**
- Create: `assets/sprites/wolf/wolf_ground_base.png` (downloaded from the tool's returned image URL)

**Interfaces:**
- Consumes: none.
- Produces: `ground_character_id` (string, SpriteCook asset ID — required by Task 3).

- [ ] **Step 1: Generate the base character**

Call `mcp__plugin_spritecook_spritecook__generate_character` with:

```json
{
  "prompt": "A top-down wolf spider game character, viewed from directly above with a slight illustrative tilt. Robust mottled brown-and-grey body with two segments (cephalothorax and rounded abdomen), eight thick hairy legs radiating symmetrically outward, subtle pale tan chevron markings on the back, a small cluster of eyes at the front. Real arachnid anatomy, correct leg count and joints. Muted, earthy, desaturated palette -- browns, tans, near-blacks. Retro/indie pixel art, crisp edges, grid-aligned, readable at small scale. Facing forward, toward the camera, in a neutral resting pose. Transparent background.",
  "perspective": "topdown"
}
```

- [ ] **Step 2: Record the character_id and download the image**

The response includes an asset ID (record it as `ground_character_id`) and an image URL or `sprite_url` — download it to `assets/sprites/wolf/wolf_ground_base.png` (create the `assets/sprites/wolf/` directory first if it doesn't exist).

- [ ] **Step 3: Visually inspect the result**

Read the downloaded PNG (via the Read tool, which can view images) and check it against `docs/art-bible.md` §2 (retro/indie pixel art, real arachnid anatomy, muted earthy palette) and the class-identity description in the design spec's audit (§3: Wolf is currently rendered via `player_wolf_spider.png`, a naturalistic wolf spider — this new version should read as the same creature, reinterpreted in pixel art). If the result clearly misses the brief (wrong anatomy, wrong palette, not pixel art), adjust the prompt and regenerate before proceeding — don't carry a bad base character into Task 3's animation spend.

- [ ] **Step 4: Note the exact anatomical/color details actually rendered**

Write down (in task notes) the specific visual details the model actually produced — exact leg color, marking pattern, body proportions — even where they weren't explicitly in the prompt. Task 4's underside character generation has to describe the *same* creature from a different angle with no direct image reference, so the more precisely this step records what was actually generated (not just what was asked for), the better Task 4's prompt can match it.

---

### Task 3: Generate Wolf's ground-facing directional animation set

**Files:** None (tool calls only; downloads happen in Task 6 via the export step).

**Interfaces:**
- Consumes: `ground_character_id` (from Task 2).
- Produces: `ground_run_id` (string, required by Task 6).

- [ ] **Step 1: Generate all 9 animation states in one guided run**

Call `mcp__plugin_spritecook_spritecook__generate_character_animations` with:

```json
{
  "character_id": "<ground_character_id from Task 2>",
  "perspective": "topdown",
  "animation_ids": ["idle", "idle_back", "idle_right", "walk_down", "walk_up", "walk_right", "attack", "hurt", "death"]
}
```

This covers: front idle/walk (default view, no extra prep cost), back idle/walk (`idle_back`/`walk_up`, each with a 12-credit back-view prep step), right-facing idle/walk (`idle_right`/`walk_right`, each with a 12-credit right-view prep step, left mirrored in Godot later — no separate `idle_left`/`walk_left` generation), and single front-facing `attack`/`hurt`/`death` (no directional variants, per spec §5's cost tradeoff). Expected cost: 12 (base, already spent in Task 2) + 20+32+32+32+32+32+20+20+20 = **252 credits** for this call, per `list_character_workflows`' published per-state costs (confirmed 2026-07-17).

- [ ] **Step 2: Poll until the run completes**

Call `mcp__plugin_spritecook_spritecook__check_character_animation_run` with the `run_id` returned by Step 1, repeating until its status is complete (this can take a while — check every 30-60 seconds rather than tight-looping). Expected: all 9 animation items report success; if any failed, inspect the failure reason before proceeding — a partial run shouldn't be exported as if complete.

- [ ] **Step 3: Record the run_id**

Task 6 needs `ground_run_id` to call `export_godot_character_package`.

---

### Task 4: Generate Wolf's underside/ceiling base character

**Files:**
- Create: `assets/sprites/wolf/wolf_underside_base.png`

**Interfaces:**
- Consumes: Task 2 Step 4's recorded visual details (for prompt consistency).
- Produces: `underside_character_id` (string, required by Task 5).

This closes the underside/belly sprite requirement `docs/superpowers/specs/2026-07-14-tunnel-visual-rework-design.md` scoped and deferred (lines 42-54, 225-229) — the user explicitly chose full animated coverage over that spec's original static-pose scope.

- [ ] **Step 1: Generate the underside base character**

`generate_character` has no reference-image parameter (unlike `generate_game_art`), so this is a from-scratch generation described in matching language to Task 2's prompt, not a transform of the ground image. Call `mcp__plugin_spritecook_spritecook__generate_character` with:

```json
{
  "prompt": "A wolf spider game character viewed from directly below, as if looking up at its underside while it clings upside-down to a ceiling overhead -- the ventral/belly view. Robust mottled brown-and-grey body with two segments (cephalothorax and rounded abdomen) [substitute the exact colors/markings recorded in Task 2 Step 4 here], eight thick hairy legs radiating symmetrically outward as seen from beneath, visible fangs/chelicerae and eye cluster if the angle shows the front. Real arachnid anatomy, correct leg count and joints. Muted, earthy, desaturated palette -- browns, tans, near-blacks. Retro/indie pixel art, crisp edges, grid-aligned, readable at small scale. Facing forward, toward the camera, neutral resting pose. Transparent background.",
  "perspective": "topdown"
}
```

- [ ] **Step 2: Record the character_id and download the image**

Record the returned asset ID as `underside_character_id`; download the image to `assets/sprites/wolf/wolf_underside_base.png`.

- [ ] **Step 3: Compare against the ground-facing base for visual consistency**

Read both `wolf_ground_base.png` and `wolf_underside_base.png` side by side. They need to read as *the same creature* (matching palette, marking style, proportions) despite being independent generations — this is the real, previously-unverified risk called out in spec §5. If they clearly don't match (different color palette, inconsistent markings, wrong scale):

- [ ] **Step 3a (only if mismatched): try a style-anchored regeneration**

Call `mcp__plugin_spritecook_spritecook__generate_game_art` with `style_asset_ids: ["<ground_character_id>"]` and the same underside-view prompt, `pixel: true`. **This produces a `generate_game_art` asset, not a `generate_character` one** — before spending Task 5's animation-generation cost against it, verify `generate_character_animations` actually accepts this asset's ID as a `character_id` (call `check_job_status` or inspect the asset via `get_asset_metadata` first, or just attempt Task 5 Step 1 with it and watch for an error). If `generate_character_animations` rejects it, fall back to regenerating via `generate_character` again (Step 1) with a more tightly-constrained prompt instead — copy exact phrases from the ground base's actual rendered details (Task 2 Step 4), not just the general brief.

---

### Task 5: Generate Wolf's underside/ceiling directional animation set

**Files:** None (tool calls only; downloads happen in Task 6).

**Interfaces:**
- Consumes: `underside_character_id` (from Task 4).
- Produces: `underside_run_id` (string, required by Task 6).

- [ ] **Step 1: Generate all 9 animation states**

Call `mcp__plugin_spritecook_spritecook__generate_character_animations` with:

```json
{
  "character_id": "<underside_character_id from Task 4>",
  "perspective": "topdown",
  "animation_ids": ["idle", "idle_back", "idle_right", "walk_down", "walk_up", "walk_right", "attack", "hurt", "death"]
}
```

Same 9 states, same expected cost (~252 credits) as Task 3 — bringing Wolf's running total to ~504 credits across both sets, matching spec §4's ~500-credit estimate.

- [ ] **Step 2: Poll until the run completes**

Call `mcp__plugin_spritecook_spritecook__check_character_animation_run` with the returned `run_id`, repeating until complete. Same failure-checking as Task 3 Step 2.

- [ ] **Step 3: Record the run_id**

Task 6 needs `underside_run_id`.

---

### Task 6: Export both Godot character packages and verify locally

**Files:**
- Create: whatever paths each `export_godot_character_package` call's `text_files` response specifies (expected under `assets/sprites/wolf/ground/` and `assets/sprites/wolf/underside/` respectively — use distinct subdirectories so the two `SpriteFrames` resources and their spritesheets never collide on name).
- Create: whatever paths each call's `asset_downloads` response specifies.

**Interfaces:**
- Consumes: `ground_run_id` (Task 3), `underside_run_id` (Task 5).
- Produces: `anim_names` (dict — the exact animation name strings found inside the exported `SpriteFrames` resources; both exports should use the same 9 logical states, so one shared naming scheme should apply to both files — required verbatim by Task 7), `ground_frames_path`, `underside_frames_path` (the two `.tres` paths — required by Task 8).

- [ ] **Step 1: Export the ground-facing package**

Call `mcp__plugin_spritecook_spritecook__export_godot_character_package` with:

```json
{
  "run_id": "<ground_run_id from Task 3>",
  "character_name": "WolfGround",
  "state_hints_by_asset_id": {
    "<idle animation asset_id>": "Idle",
    "<idle_back animation asset_id>": "IdleUp",
    "<idle_right animation asset_id>": "IdleRight",
    "<walk_down animation asset_id>": "WalkDown",
    "<walk_up animation asset_id>": "WalkUp",
    "<walk_right animation asset_id>": "WalkRight",
    "<attack animation asset_id>": "Attack",
    "<hurt animation asset_id>": "Hurt",
    "<death animation asset_id>": "Death"
  }
}
```

(Fill in the actual per-animation asset IDs from Task 3's `check_character_animation_run` result — `run_id` alone lets SpriteCook infer states from the preset, so `state_hints_by_asset_id` here is a safety net to pin exact naming, not strictly required.)

- [ ] **Step 2: Write and download the ground package**

For each entry in the response's `text_files` array, write its `content` to its `path` exactly, prefixed under `assets/sprites/wolf/ground/` if the tool's returned paths don't already namespace it (rename to avoid collision with the underside export in Step 4 below). For each entry in `asset_downloads`, download the signed `url` to its `path`. Record the written `SpriteFrames` `.tres` path as `ground_frames_path`.

- [ ] **Step 3: Export the underside/ceiling package**

Repeat Step 1 with `run_id: "<underside_run_id from Task 5>"`, `character_name: "WolfUnderside"`, and `state_hints_by_asset_id` built from Task 5's animation asset IDs (same state-hint vocabulary).

- [ ] **Step 4: Write and download the underside package**

Same as Step 2, writing under `assets/sprites/wolf/underside/` and recording the path as `underside_frames_path`.

- [ ] **Step 5: Record the exact animation names**

Open both `SpriteFrames` `.tres` files and find each `"name": &"..."` entry under their `animations` arrays. Record the mapping from this plan's logical keys (`idle`, `idle_back`, `idle_right`, `walk_down`, `walk_up`, `walk_right`, `attack`, `hurt`, `death`) to the literal strings found — expected to match between the two files since both used identical `state_hints_by_asset_id` values, but confirm rather than assume. **If either differs from the `Idle`/`IdleUp`/`IdleRight`/`WalkDown`/`WalkUp`/`WalkRight`/`Attack`/`Hurt`/`Death` used in Steps 1/3, use the names actually found** — Task 7's `ANIM_NAMES` dictionary must match both resources exactly (if the two files ever disagree on naming, that's itself a problem to flag before continuing, since `Player` will only own one `ANIM_NAMES` map shared by both).

- [ ] **Step 6: Fix animation looping if needed**

In both `.tres` files, confirm `attack`, `hurt`, and `death`'s entries have `"loop": false` (idle/walk should have `"loop": true`). If either export defaulted all animations to looping, edit `attack`/`hurt`/`death`'s `loop` values to `false` directly — Task 8's animation-state guard depends on `AnimatedSprite2D.is_playing()` becoming `false` once these finish, which only happens for non-looping animations.

- [ ] **Step 7: Headless import check**

Run: `~/.local/bin/godot --headless --path . --import`
Expected: no new errors mentioning the Wolf files just added (existing unrelated warnings in a fresh checkout are fine — check specifically for `wolf` or the new file paths in the output).

- [ ] **Step 8: Commit**

```bash
git add assets/sprites/wolf/
git commit -m "Add Wolf ground + underside SpriteFrames from SpriteCook (Category 0)"
```

---

### Task 7: Add and verify the facing→animation helper

**Files:**
- Modify: `entities/player/player.gd` (add constants and a pure static function; no wiring into gameplay yet — that's Task 8).
- Test: a temporary scratch script at repo root, deleted at the end of this task.

**Interfaces:**
- Consumes: `anim_names` (from Task 6 Step 5).
- Produces: `Player.ANIM_NAMES` (Dictionary) and `Player._locomotion_animation_for(facing_dir: Vector2, moving: bool) -> Dictionary` (returns `{"animation": String, "flip_h": bool}`) — both consumed by Task 8.

- [ ] **Step 1: Add the animation-name lookup and the pure helper to player.gd**

Add near the top of `entities/player/player.gd`, after the existing `const` declarations (around line 47, after `DecoyData`):

```gdscript
## Maps this pipeline's logical animation keys to the literal animation
## names inside the exported SpriteFrames resources (assets/sprites/wolf/,
## Category 0 -- see docs/superpowers/specs/2026-07-17-art-pipeline-
## design.md §5) -- shared by both the ground and underside sets, which
## use identical animation names by construction (Task 6). Update this
## dictionary, not the call sites, if SpriteCook's Godot export ever names
## animations differently.
const ANIM_NAMES := {
	"idle": "Idle", "idle_back": "IdleUp", "idle_right": "IdleRight",
	"walk_down": "WalkDown", "walk_up": "WalkUp", "walk_right": "WalkRight",
	"attack": "Attack", "hurt": "Hurt", "death": "Death",
}
```

(Replace the right-hand-side string values with whatever Task 6 Step 5 actually recorded, if different.)

Add this pure static function near the bottom of the file, after `_dominant_dir()` (after line 401):

```gdscript
## Facing-direction -> AnimatedSprite2D animation name + horizontal mirror
## flag. Replaces the old sprite.rotation = facing.angle() approach: the
## Phase 2 faux-3D wall renderer (world/maze/maze_renderer.gd) never
## rotates anything -- every wall's lighter top-face/darker front-face is
## anchored to a fixed world-space edge -- so a rotating creature sprite
## would be the one thing fighting that convention. `facing_dir` is always
## exactly one of the four cardinal unit vectors (see _dominant_dir()).
## Which SpriteFrames resource this animation name plays against (ground
## vs. underside) is decided separately, by plane -- see
## _on_plane_changed() in Task 8.
static func _locomotion_animation_for(facing_dir: Vector2, moving: bool) -> Dictionary:
	if facing_dir.y < 0.0:
		return {"animation": ANIM_NAMES["walk_up"] if moving else ANIM_NAMES["idle_back"], "flip_h": false}
	if facing_dir.y > 0.0:
		return {"animation": ANIM_NAMES["walk_down"] if moving else ANIM_NAMES["idle"], "flip_h": false}
	return {"animation": ANIM_NAMES["walk_right"] if moving else ANIM_NAMES["idle_right"], "flip_h": facing_dir.x < 0.0}
```

- [ ] **Step 2: Write a scratch verification script**

Create `check_locomotion_animation.gd` at the repo root:

```gdscript
extends SceneTree

func _initialize() -> void:
	var cases := [
		[Vector2.DOWN, false, Player.ANIM_NAMES["idle"], false],
		[Vector2.DOWN, true, Player.ANIM_NAMES["walk_down"], false],
		[Vector2.UP, false, Player.ANIM_NAMES["idle_back"], false],
		[Vector2.UP, true, Player.ANIM_NAMES["walk_up"], false],
		[Vector2.RIGHT, false, Player.ANIM_NAMES["idle_right"], false],
		[Vector2.RIGHT, true, Player.ANIM_NAMES["walk_right"], false],
		[Vector2.LEFT, false, Player.ANIM_NAMES["idle_right"], true],
		[Vector2.LEFT, true, Player.ANIM_NAMES["walk_right"], true],
	]
	var failures := 0
	for c in cases:
		var result: Dictionary = Player._locomotion_animation_for(c[0], c[1])
		if result.animation != c[2] or result.flip_h != c[3]:
			print("FAIL facing=%s moving=%s got=%s want_anim=%s want_flip=%s" % [c[0], c[1], result, c[2], c[3]])
			failures += 1
	print("PASS" if failures == 0 else "FAILURES: %d" % failures)
	quit()
```

- [ ] **Step 3: Run it and verify it passes**

Run: `~/.local/bin/godot --headless -s check_locomotion_animation.gd`
Expected: `PASS` printed, no `FAIL` lines. (This is a bare `-s` script run, not a scene — safe here because `_locomotion_animation_for` is a pure static function on a `class_name` global and touches no autoload, per this project's established headless-testing gotcha.)

- [ ] **Step 4: Delete the scratch script**

```bash
rm check_locomotion_animation.gd
```

Confirm `git status` shows no leftover scratch file (and no stray `.gd.uid` sidecar) before moving on.

- [ ] **Step 5: Commit**

```bash
git add entities/player/player.gd
git commit -m "Player: add facing-to-animation lookup (Category 0, no wiring yet)"
```

---

### Task 8: Wire Player onto AnimatedSprite2D with plane-swapped SpriteFrames

**Files:**
- Modify: `entities/player/player.tscn:58-61` (the `Sprite` node)
- Modify: `entities/player/player.gd:21, 47, 76-114, 116-129, 332-338, 459-464`

**Interfaces:**
- Consumes: `Player.ANIM_NAMES`, `Player._locomotion_animation_for()` (Task 7); `ground_frames_path`, `underside_frames_path` (Task 6).
- Produces: `Player._update_locomotion_animation()`, `Player._on_plane_changed()` (both private, called automatically) — no external consumers.

- [ ] **Step 1: Swap the Sprite node's type in player.tscn**

In `entities/player/player.tscn`, replace the `9_wolf` texture ext_resource (line 12) with an ext_resource pointing at the ground-facing `SpriteFrames` `.tres` (`ground_frames_path` from Task 6), and change the `Sprite` node (lines 58-61) from:

```
[node name="Sprite" type="Sprite2D" parent="."]
texture_filter = 1
scale = Vector2(0.45, 0.45)
texture = ExtResource("9_wolf")
```

to:

```
[node name="Sprite" type="AnimatedSprite2D" parent="."]
texture_filter = 1
scale = Vector2(0.45, 0.45)
sprite_frames = ExtResource("9_wolf_ground_frames")
animation = &"Idle"
autoplay = "Idle"
```

(Use the exact `ext_resource` `id` Godot assigns when you add the resource — `9_wolf_ground_frames` above is illustrative; keep whatever numbering the `.tscn`'s `load_steps` header already uses, incrementing as needed. The underside `SpriteFrames` resource does *not* need its own ext_resource in the `.tscn` — Step 3 below preloads it directly in `player.gd` instead, since it's swapped in by code, not authored on the node.)

**The `scale = Vector2(0.45, 0.45)` above was tuned for the old texture's 92×92px source** (the original wolf sprite was scaled down to roughly tile-size, per `art-bible.md` §2: "A creature occupying one tile should read clearly at roughly [48×48] size"). SpriteCook's topdown character workflow will very likely export frames at a different resolution. Before finalizing this step: check the actual frame dimensions in the ground `SpriteFrames` `.tres` (each `AtlasTexture`'s `region` width/height, or the source texture's total size divided by frame count), and recompute the scale so the sprite's on-screen size stays close to the original ~41px visual footprint the design spec's audit measured (`world/maze/maze_renderer.gd`'s `ENTITY_VISUAL_HALF_EXTENT = 24.0`, i.e. ~48px full width) — e.g. if the new frames are 512×512, the equivalent scale is roughly `48.0 / 512.0 ≈ 0.09`, not `0.45`. Get this number from the real exported frame size, not by assumption. Apply the same scale to whatever the underside frames turn out to be sized at too (check they match — both exports came from independent generations, so their frame dimensions aren't guaranteed identical; if they differ, the scale may need to differ per resource, applied at swap time in Step 4 below rather than fixed once on the node).

- [ ] **Step 2: Update the sprite's declared type in player.gd**

Change line 21 from:

```gdscript
@onready var sprite: Sprite2D = $Sprite
```

to:

```gdscript
@onready var sprite: AnimatedSprite2D = $Sprite
```

- [ ] **Step 3: Preload both SpriteFrames resources**

Add near the top of `entities/player/player.gd`, after the `ANIM_NAMES` constant added in Task 7:

```gdscript
## The two animation sets a Player swaps between via _on_plane_changed()
## below -- ground-facing (the default/rest state, also authored directly
## on the Sprite node in player.tscn) and underside/ceiling (Category 0 --
## closes the deferred Phase 2 underside-sprite gap,
## docs/superpowers/specs/2026-07-14-tunnel-visual-rework-design.md lines
## 225-229). Both preloaded here, not just the underside one, so
## _on_plane_changed() never has to guess/cache whatever the node's
## sprite_frames happened to be first.
const GROUND_FRAMES: SpriteFrames = preload("res://assets/sprites/wolf/ground/wolf_ground_frames.tres")
const UNDERSIDE_FRAMES: SpriteFrames = preload("res://assets/sprites/wolf/underside/wolf_underside_frames.tres")
```

(Replace both preload paths with the actual `ground_frames_path`/`underside_frames_path` from Task 6 — `GROUND_FRAMES` should point at the same resource `player.tscn`'s `Sprite` node references in Step 1.)

- [ ] **Step 4: Wire the plane-changed swap**

In `_ready()`, add this connection near the other signal connections (after the `_status.effect_expired.connect(...)` line, around line 83):

```gdscript
	_plane.plane_changed.connect(_on_plane_changed)
```

Add this new method after `_update_sprite_tint()` (after line 298):

```gdscript
## Swaps which SpriteFrames resource is active whenever this Player
## crosses between ground and ceiling -- the underside/ceiling set closes
## the gap docs/superpowers/specs/2026-07-14-tunnel-visual-rework-design.md
## deferred (lines 225-229): "a fixed top-down camera looking at an
## upside-down spider would actually see its belly, not its back." Both
## SpriteFrames resources share the same animation names (ANIM_NAMES), so
## whichever one is currently playing keeps playing under the new
## resource -- only the frames actually shown change, not which named
## animation is selected.
func _on_plane_changed(plane: Level.Layer) -> void:
	var current_animation := sprite.animation
	sprite.sprite_frames = UNDERSIDE_FRAMES if plane == Level.Layer.CEILING else GROUND_FRAMES
	sprite.play(current_animation)
```

- [ ] **Step 5: Remove the rotation line and add the locomotion-animation call**

In `_physics_process()`, change lines 121-129 from:

```gdscript
	var dir := _dominant_dir(Input.get_vector("move_left", "move_right", "move_up", "move_down"))
	if dir != Vector2i.ZERO:
		facing = Vector2(dir)
		sprite.rotation = facing.angle() # sprite drawn facing east (rotation 0)
		_mover.try_step(dir)
	else:
		# No input this frame: drop any queued step so a step finishing right
		# after release doesn't auto-continue into a stale buffered direction.
		_mover.cancel_buffer()
```

to:

```gdscript
	var dir := _dominant_dir(Input.get_vector("move_left", "move_right", "move_up", "move_down"))
	if dir != Vector2i.ZERO:
		facing = Vector2(dir)
		_mover.try_step(dir)
	else:
		# No input this frame: drop any queued step so a step finishing right
		# after release doesn't auto-continue into a stale buffered direction.
		_mover.cancel_buffer()
	_update_locomotion_animation()
```

- [ ] **Step 6: Add the `_update_locomotion_animation()` method**

Add this method right after `_physics_process()` (after line 177, before `bind_level()`):

```gdscript
## Drives the AnimatedSprite2D's idle/walk state every physics frame from
## the pure Player._locomotion_animation_for() lookup, without interrupting
## an in-progress attack/hurt/death one-shot (those aren't in this set, so
## the guard below only ever holds locomotion back, never the reverse).
## Works unchanged regardless of which SpriteFrames resource (ground or
## underside) is currently assigned -- see _on_plane_changed().
func _update_locomotion_animation() -> void:
	if sprite.is_playing() and sprite.animation not in [
		ANIM_NAMES["idle"], ANIM_NAMES["idle_back"], ANIM_NAMES["idle_right"],
		ANIM_NAMES["walk_down"], ANIM_NAMES["walk_up"], ANIM_NAMES["walk_right"],
	]:
		return
	var choice := _locomotion_animation_for(facing, _mover.is_moving())
	sprite.flip_h = choice.flip_h
	if sprite.animation != choice.animation:
		sprite.play(choice.animation)
```

- [ ] **Step 7: Wire the attack animation**

In `_melee()`, change the start of the function (lines 332-338) from:

```gdscript
func _melee() -> void:
	if _melee_left > 0.0:
		return
	_melee_left = melee_cooldown
	var push := _dominant_dir(facing)
	var target := global_position + facing * float(_mover.tile_size)
	CombatFx.spawn_slash(get_parent(), target, facing) # always shows, hit or miss
```

to:

```gdscript
func _melee() -> void:
	if _melee_left > 0.0:
		return
	_melee_left = melee_cooldown
	sprite.flip_h = facing.x < 0.0
	sprite.play(ANIM_NAMES["attack"])
	var push := _dominant_dir(facing)
	var target := global_position + facing * float(_mover.tile_size)
	CombatFx.spawn_slash(get_parent(), target, facing) # always shows, hit or miss
```

- [ ] **Step 8: Wire the hurt animation**

In `_ready()`, change line 107 from:

```gdscript
	health.damaged.connect(func(_amount: float) -> void: CombatFx.flash(sprite))
```

to:

```gdscript
	health.damaged.connect(func(_amount: float) -> void:
		CombatFx.flash(sprite)
		sprite.flip_h = facing.x < 0.0
		sprite.play(ANIM_NAMES["hurt"]))
```

- [ ] **Step 9: Wire the death animation**

Change `_on_died()` (lines 459-464) from:

```gdscript
func _on_died() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	EventBus.player_died.emit()
```

to:

```gdscript
func _on_died() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	sprite.flip_h = facing.x < 0.0
	sprite.play(ANIM_NAMES["death"])
	EventBus.player_died.emit()
```

- [ ] **Step 10: Headless import check**

Run: `~/.local/bin/godot --headless --path . --import`
Expected: no new errors referencing `player.tscn` or `player.gd`.

- [ ] **Step 11: Headless boot smoke test**

Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -i "error\|warning\|script"`
Expected: no new output referencing `player.gd`, `player.tscn`, `Sprite`, or `AnimatedSprite2D` beyond whatever pre-existing warnings the project already has (check against a baseline run before this task if unsure).

- [ ] **Step 12: Commit**

```bash
git add entities/player/player.tscn entities/player/player.gd
git commit -m "Player: replace Sprite2D+rotation with plane-aware AnimatedSprite2D (Category 0)"
```

---

### Task 9: Real windowed screenshot verification, both planes

**Files:**
- Create (temporary, deleted at the end of this task): `check_wolf_animations.gd`, `check_wolf_animations.tscn` (and its `.gd.uid` sidecar).
- Create (temporary, sent to the user then deleted): PNG screenshots under `$CLAUDE_JOB_DIR/tmp` (or the equivalent scratch directory for this session).

**Interfaces:**
- Consumes: the wired `Player` scene (Task 8).
- Produces: nothing consumed by later tasks — this is the render-verified gate itself (spec §9).

- [ ] **Step 1: Write the scratch verification scene**

Create `check_wolf_animations.tscn` at the repo root:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://check_wolf_animations.gd" id="1_check"]

[node name="Check" type="Node"]
script = ExtResource("1_check")
```

- [ ] **Step 2: Write the scratch verification script**

Create `check_wolf_animations.gd` at the repo root. This drives Wolf through all 6 non-lethal states on the ground plane, transitions to the ceiling, repeats the same 6 states there (proving the plane-swap actually swaps art, not just that ground art works), then triggers death last, on the ceiling, as the final state:

```gdscript
extends Node

const World := preload("res://world/world.tscn")
const NON_LETHAL_STATES := ["idle", "walk_right", "walk_up", "walk_down", "attack", "hurt"]

var _world: Node
var _player: Node
var _plane_label := "ground"
var _i := 0
var _did_transition := false
var _did_death := false


func _ready() -> void:
	_world = World.instantiate()
	get_tree().root.add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")
	_drive_next_state()


func _drive_next_state() -> void:
	if _i >= NON_LETHAL_STATES.size():
		if not _did_transition:
			_did_transition = true
			_i = 0
			_plane_label = "ceiling"
			_player._plane.transition()
			await get_tree().process_frame
			_drive_next_state()
			return
		if not _did_death:
			_did_death = true
			_player.health.take_damage(100000.0)
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().create_timer(0.15).timeout
			var img := get_viewport().get_texture().get_image()
			img.save_png("res://scratch_wolf_ceiling_death.png")
		get_tree().quit()
		return
	var state: String = NON_LETHAL_STATES[_i]
	_i += 1
	# GridMover's default step_time is 0.12s (grid_mover.gd) -- a walk state
	# must be screenshotted well before the step completes and _mover falls
	# back to not-moving, or the capture will show idle instead of the walk
	# animation. Attack/hurt aren't time-boxed the same way, so they get a
	# longer wait to land mid-animation instead of on frame 0.
	var wait := 0.05
	match state:
		"idle":
			pass # already idle at spawn / after transition
		"walk_right":
			_player.facing = Vector2.RIGHT
			_player._mover.try_step(Vector2i.RIGHT)
		"walk_up":
			_player.facing = Vector2.UP
			_player._mover.try_step(Vector2i.UP)
		"walk_down":
			_player.facing = Vector2.DOWN
			_player._mover.try_step(Vector2i.DOWN)
		"attack":
			_player._melee()
			wait = 0.15
		"hurt":
			_player.health.take_damage(1.0) # bypasses Hurtbox -- no apply_hit_fall() plane knockdown
			wait = 0.15
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(wait).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://scratch_wolf_%s_%s.png" % [_plane_label, state])
	_drive_next_state()
```

(This directly manipulates `Player`'s public/underscore-prefixed fields and methods — `facing`, `_mover`, `_plane`, `health`, `_melee()` — rather than simulating real `Input` events, matching how this project's existing scratch-scene convention drives gameplay code directly for a headless/windowed check. `health.take_damage()` is used instead of going through `Hurtbox.receive_hit()` specifically so the ceiling "hurt" test doesn't trigger `PlaneComponent.apply_hit_fall()`'s automatic knockdown-to-ground, which would undermine the test by transitioning planes mid-check.)

- [ ] **Step 3: Run it windowed (not headless)**

Run: `GALLIUM_DRIVER=d3d12 ~/.local/bin/godot --path . res://check_wolf_animations.tscn`
Expected: the window opens, briefly shows Wolf running through idle → walk (right/up/down) → attack → hurt on the ground, transitions to the ceiling and repeats the same six states (now on the underside art), then dies on the ceiling, and the window closes on its own. Thirteen `scratch_wolf_*.png` files appear at the repo root (6 ground + 6 ceiling + 1 death).

- [ ] **Step 4: Move the screenshots to job scratch space and send them to the user**

```bash
mkdir -p "$CLAUDE_JOB_DIR/tmp/wolf_screenshots"
mv scratch_wolf_*.png "$CLAUDE_JOB_DIR/tmp/wolf_screenshots/"
```

Use `SendUserFile` with all thirteen PNGs, `status: "normal"`, asking the user to visually confirm each state reads correctly (on-style, correct facing, no rotation artifacts, attack/hurt/death read clearly, **and that the ceiling shots genuinely show the underside/belly rather than the same ground art reused**) before Task 10 marks the manifest entries `approved`.

- [ ] **Step 5: Delete the scratch scene/script**

```bash
rm -f check_wolf_animations.gd check_wolf_animations.tscn check_wolf_animations.gd.uid
```

Confirm `git status` shows nothing left over from this task.

- [ ] **Step 6: Wait for the user's visual sign-off**

Do not proceed to Task 10's `status: "approved"` manifest entries until the user has actually looked at the screenshots and confirmed both the ground and ceiling sets. If they flag a problem (wrong facing, visible seam, an animation that reads wrong, or a ceiling shot that doesn't actually look like an underside view), fix it before moving on — this gate exists specifically because this project has repeatedly found visual bugs no automated check caught.

---

### Task 10: Record real cost, update the manifest, art-bible, and tunnel-rework spec, final commit

**Files:**
- Create: `assets/art-manifest.json`
- Modify: `docs/art-bible.md` (§2's "Confirmed" section, and the Wolf reference-art pointer)
- Modify: `docs/superpowers/specs/2026-07-17-art-pipeline-design.md` §9 (record the real cost)
- Modify: `docs/superpowers/specs/2026-07-14-tunnel-visual-rework-design.md` (mark the underside-sprite deferral as resolved)

**Interfaces:**
- Consumes: `starting_balance` (Task 1), `ground_character_id`/`ground_run_id` (Tasks 2-3), `underside_character_id`/`underside_run_id` (Tasks 4-5), the user's approval (Task 9).
- Produces: nothing — this is the plan's final task.

- [ ] **Step 1: Check the credit balance again**

Call `mcp__plugin_spritecook_spritecook__get_credit_balance` again. Compute `starting_balance - total_credits` = actual credits spent on Wolf (both sets combined). Compare against the ~504-credit estimate (252 × 2) from Tasks 3/5.

- [ ] **Step 2: Write the asset manifest**

Create `assets/art-manifest.json`:

```json
{
  "assets": [
    {
      "id": "wolf-idle-anchor",
      "category": 0,
      "role": "player_class_wolf",
      "character_id": "<ground_character_id from Task 2>",
      "run_id": "<ground_run_id from Task 3>",
      "still_local": "assets/sprites/wolf/wolf_ground_base.png",
      "frames_local": "assets/sprites/wolf/ground/",
      "animations": {
        "idle": "<idle animation asset_id>",
        "idle_back": "<idle_back animation asset_id>",
        "idle_right": "<idle_right animation asset_id>",
        "walk_down": "<walk_down animation asset_id>",
        "walk_up": "<walk_up animation asset_id>",
        "walk_right": "<walk_right animation asset_id>",
        "attack": "<attack animation asset_id>",
        "hurt": "<hurt animation asset_id>",
        "death": "<death animation asset_id>"
      },
      "underside_character_id": "<underside_character_id from Task 4>",
      "underside_run_id": "<underside_run_id from Task 5>",
      "underside_animations": {
        "idle": "<idle animation asset_id>",
        "idle_back": "<idle_back animation asset_id>",
        "idle_right": "<idle_right animation asset_id>",
        "walk_down": "<walk_down animation asset_id>",
        "walk_up": "<walk_up animation asset_id>",
        "walk_right": "<walk_right animation asset_id>",
        "attack": "<attack animation asset_id>",
        "hurt": "<hurt animation asset_id>",
        "death": "<death animation asset_id>"
      },
      "status": "approved"
    }
  ]
}
```

(Only set `"status": "approved"` if Task 9 Step 6's user sign-off actually happened — otherwise use `"generated"` and follow up once it does.)

- [ ] **Step 3: Update art-bible.md's "Confirmed" ground truth**

In `docs/art-bible.md` §2, update the bullet describing sprite facing to reflect the new reality: `Player`'s sprite no longer rotates; it plays a directional `AnimatedSprite2D` animation (front/back/right, mirrored to left) selected by `Player._locomotion_animation_for()`, matching the faux-3D wall renderer's fixed-orientation convention, and swaps to a full underside/ceiling animation set on `PlaneComponent.plane_changed` (see `docs/superpowers/specs/2026-07-17-art-pipeline-design.md` §5 for the full reasoning). Note that `Enemy` still rotates and has no underside set yet (`enemy.gd:589`) — that conversion is Category 2's scope, not done here.

- [ ] **Step 4: Mark the tunnel-rework spec's underside deferral as resolved**

In `docs/superpowers/specs/2026-07-14-tunnel-visual-rework-design.md`, near the "Underside sprite — deferred" note (lines 225-229) and the "No underside/belly sprite in Phase 2" non-goal (lines 244-245), add a note that Category 0 of the 2026-07-17 art pipeline closed this for Wolf specifically (full animated set, not just the originally-scoped static pose), with Warden/Ogre/Echo following in Category 2 — link to `docs/superpowers/specs/2026-07-17-art-pipeline-design.md` §5.

- [ ] **Step 5: Update the design spec's cost checkpoint with the real number**

In `docs/superpowers/specs/2026-07-17-art-pipeline-design.md` §9, replace the "~500-credit estimate" language with the confirmed actual cost from Step 1, and note whether the full-roadmap estimate (5,000-6,000 credits) needs revising as a result.

- [ ] **Step 6: Commit**

```bash
git add assets/art-manifest.json docs/art-bible.md docs/superpowers/specs/2026-07-17-art-pipeline-design.md docs/superpowers/specs/2026-07-14-tunnel-visual-rework-design.md
git commit -m "Category 0 complete: Wolf animated on both planes, real cost recorded"
```

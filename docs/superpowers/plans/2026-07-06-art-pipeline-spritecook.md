# Burrow — Slice 1 Art Pipeline (SpriteCook)

**Date:** 2026-07-06
**Status:** Approved plan — not yet executed
**Depends on:** [`../specs/2026-07-06-burrow-rebuild-design.md`](../specs/2026-07-06-burrow-rebuild-design.md)

## Decisions (locked)

- **Style:** pixel art (SpriteCook pixel mode). Project already sets
  `textures/canvas_textures/default_texture_filter=0` (nearest) — pixel-ready.
- **Facing:** one top-down sprite per creature, **drawn facing east (+X)**, rotated
  in code to `velocity.angle()`. Directional frame sets are a later upgrade.
- **Models:** `gemini-3.1-flash-image-preview` default; `gemini-3-pro-image-preview`
  only for the player style anchor. `smart_crop_mode="tightest"`.

Until execution, entities keep their placeholder `Polygon2D` visuals and the maze
draws flat rects — the game runs fine as-is.

## Asset inventory

| # | Asset | Size (px, pre-scale) | Frames | SpriteCook step | Godot target |
|---|-------|----------------------|--------|-----------------|--------------|
| 1 | Maze tileset (floor+walls) | 32 tiles | 15-piece | `generate_tileset` dual-grid, top-down | `TileMapLayer` (replaces `maze_renderer.gd`) |
| 2 | Player spider | ~32 | idle + walk | `generate_game_art` → `animate` | `AnimatedSprite2D` in `player.tscn` |
| 3 | Enemy "Rival Spider" | ~32 | idle + walk | variant of #2 (recolor) | `EnemyType.sprite_frames` |
| 4 | Larva | ~20 | wander (+caught later) | `generate_game_art` → `animate` | `AnimatedSprite2D` in `larva.tscn` |
| 5 | Web shot | ~12 | 1–3 | `generate_game_art` | `Sprite2D`/`AnimatedSprite2D` in `web_shot.tscn` |
| 6 | Web trap (+ spent) | ~40 | 1 (+shimmer later) | `generate_game_art` | `Visual` node in `web_trap.tscn` |
| 7 | Game icon | 128 | 1 | `generate_game_art` | `project.godot` icon (replace `icon.svg`) |

Tiles/entities scale up to the in-game grid (`TILE_SIZE = 48`) via `texture_scale`
/ node scale; keep source art small so it stays crisp.

## Phases

### Phase 0 — setup (near-free)
1. Authenticate the SpriteCook MCP; run `get_credit_balance` before any batch.
2. Create `spritecook-assets.json` at repo root — track every `asset_id`
   (`{asset_id, sha12, label}` per the workflow's manifest pattern).
3. **Generate the player spider first as the style anchor** (pro model). Save its
   `asset_id`; pass it as `style_asset_ids` / `reference_asset_id` on every later
   generation so the whole set is cohesive. Optionally `save_private_preset` to
   freeze model + style refs.

### Phase 1 — six core assets (delete all placeholder polygons)
Order: player → enemy (variant of anchor) → larva → tileset → web shot → web trap.
Then import (below).

### Phase 2 — polish
Attack / hurt / death anims, a struggling "caught" larva, icon, HUD trim
(themed bars + HP/hunger icons), ambient maze detail (egg sacs, bones).

## Prompt sketches (style anchor sets the tone)

- **Player spider:** "top-down pixel-art spider, amber/tan body, 8 legs splayed,
  facing right/east, dark maze creature, transparent background, game sprite."
- **Enemy:** reuse anchor as style ref; "same top-down pixel spider recolored
  deep red, meaner silhouette, facing east."
- **Larva:** "tiny top-down pixel grub/larva, pale green segmented body, facing
  east, transparent background."
- **Web shot:** "small pixel-art web/silk projectile blob, off-white, glowing."
- **Web trap:** "top-down pixel-art spiderweb snare on the ground, radial threads,
  faint sheen" + a torn/"spent" variant.
- **Tileset:** "top-down pixel-art dungeon tunnel, dark earth floor vs stone
  walls, dual-grid autotile terrain."

## Godot integration steps

Small, isolated edits — components, collision, nav, and fog are untouched.

- **Entities (2–4):** `spritecook-use-assets-in-godot` — spritesheet → `SpriteFrames`
  → `AnimatedSprite2D`. Replace each scene's `Polygon2D` "Visual"/"Facing"/"Head"
  with the `AnimatedSprite2D`. Draw art facing **east** so rotation is correct.
  - `player.gd`: rotate the sprite child to `velocity.angle()` (not the body);
    play `walk` when moving, `idle` when still.
  - `enemy.gd`: point the existing `facing_visual` at the new sprite (it already
    rotates to the path direction).
  - `larva.gd`: already rotates the whole node — just add the sprite.
  - Assign the enemy's `SpriteFrames` to `resources/enemies/rival_spider.tres`
    (`sprite_frames` export already exists).
- **Maze tileset (1):** `spritecook-use-dual-grid-tilesets` → build a `TileSet`,
  drop a `TileMapLayer` into `level.tscn`, and in `level.gd` set cells from the
  `MazeData` grid using the dual-grid mask. Keep the separate collision / occluder
  / nav build (unchanged); optionally migrate wall collision into the tileset later.
- **Web shot/trap (5,6):** swap the `Polygon2D` for a `Sprite2D` (shot) /
  `AnimatedSprite2D` (trap shimmer); logic scripts need no change.
- **Icon (7):** save PNG, set as `project.godot` icon, retire `icon.svg`.

## Cost & safety

- Check `get_credit_balance` before Phase 1; generate the anchor, review, iterate,
  *then* batch the rest with it as the style ref.
- Never paste/print API keys; use MCP tools + presigned URLs only.
- Save every `asset_id` to `spritecook-assets.json`; recover via
  `list_recent_assets` if lost.

## Verify after import

Run the headless recipe (Godot 4.7 at `~/.local/bin/godot`):
`godot --headless --path . res://world/world.tscn --quit-after 600` and grep
stderr for `error|warning` — confirms scenes still load with real textures.

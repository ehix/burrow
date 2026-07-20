class_name TileTextureVariant
extends RefCounted
## Deterministic per-tile crop + flip so adjacent tiles drawn from the
## same small source texture don't show pixel-identical content (root
## cause: draw_texture_rect(tile=true) always resets UV sampling to a
## draw call's own rect origin, not to the rect's position in world
## space -- every FloorRenderer/MazeRenderer/WallOverdrawMask/
## WaterTileLayer tile ended up showing the source texture's identical
## top-left corner. See docs/superpowers/specs/2026-07-20-tile-texture-
## variation-design.md for the full writeup, including how this was
## verified). Keyed purely by tile coordinate -- no time/frame
## dependence, so a given tile always renders the same way and
## queue_redraw() never causes visible jitter, and so two independent
## draw sites for the SAME tile (MazeRenderer's own wall draw and
## WallOverdrawMask's occluded-overdraw repaint) are guaranteed to agree
## without duplicating this logic -- both just call draw_varied() with
## the same tile and get the identical result.


## Pure: given a tile, the size of the rect it'll be drawn into, and the
## source texture's own size, returns the crop (in texture pixels) and
## flip flags to use. Split out from draw_varied() so it's directly
## unit-testable without a scene tree, matching this codebase's
## established pattern for renderer logic (MazeRenderer.wall_occludes_
## extent(), overdraw_alpha_for_offset(), etc.).
static func variant_for(tile: Vector2i, dest_size: Vector2, texture_size: Vector2) -> Dictionary:
	# absi() matters here: GDScript's %% keeps the dividend's sign, so a
	# negative hash() would otherwise produce a negative offset.
	var h := absi(hash(tile))
	var max_x := maxi(0, int(texture_size.x) - int(dest_size.x))
	var max_y := maxi(0, int(texture_size.y) - int(dest_size.y))
	var offset_x := 0 if max_x == 0 else (h % (max_x + 1))
	# Divide by a distinct prime before the y modulo so x/y offsets, and
	# the flip bits below, aren't visibly correlated with each other.
	var offset_y := 0 if max_y == 0 else ((h / 4099) % (max_y + 1))
	var flip_h := bool((h / 65537) & 1)
	var flip_v := bool((h / 131111) & 1)
	return {
		"src_rect": Rect2(offset_x, offset_y, dest_size.x, dest_size.y),
		"flip_h": flip_h,
		"flip_v": flip_v,
	}


## Draws `texture` into `dest_rect` on `canvas_item`, using variant_for()'s
## per-tile crop and flip -- must be called from inside canvas_item's own
## _draw() (Godot's draw_* methods only work mid-draw-pass). Replaces
## draw_texture_rect(texture, dest_rect, tile=true, modulate) at every
## call site that used to rely on that flag; draw_texture_rect_region has
## no repeat/tile behavior of its own; regardless, it always stretches
## src_rect to fill dest_rect exactly once (verified during design).
## Flipping is done via a canvas transform (draw_set_transform with a
## negative scale axis around the tile's own center), NOT via a
## negative-size dest Rect2 -- that's the usual Godot flip idiom, but on
## this project's actual runtime (GL Compatibility / Mesa d3d12 on WSL2)
## draw_texture_rect_region silently ignores the sign of a negative-size
## dest rect's width/height and just draws abs(size) forward from
## `position` -- so a flipped tile lands shifted by its own size instead
## of mirrored in place, leaving its true grid cell completely undrawn.
## In a gapless tile grid that reads as a hole showing whatever's behind
## (black, in this game's dark maze) -- confirmed via isolated repro
## (a dense FloorRenderer-style grid rendered with the old negative-rect
## code left whole rows/columns undrawn wherever flip_h/flip_v tiles
## landed). Not worth chasing further as a driver quirk since roughly
## half of all tiles get flip_h=true; the transform sidesteps it cleanly
## for both axes. draw_texture_rect_region is always called with a
## positive-size rect centered on the origin; the transform is reset to
## identity immediately after so it doesn't leak into later draw calls.
static func draw_varied(canvas_item: CanvasItem, texture: Texture2D, dest_rect: Rect2, tile: Vector2i, modulate: Color = Color.WHITE) -> void:
	var variant := variant_for(tile, dest_rect.size, texture.get_size())
	if not variant.flip_h and not variant.flip_v:
		canvas_item.draw_texture_rect_region(texture, dest_rect, variant.src_rect, modulate)
		return
	var flip_scale := Vector2(-1.0 if variant.flip_h else 1.0, -1.0 if variant.flip_v else 1.0)
	var center := dest_rect.position + dest_rect.size * 0.5
	canvas_item.draw_set_transform(center, 0.0, flip_scale)
	canvas_item.draw_texture_rect_region(texture, Rect2(-dest_rect.size * 0.5, dest_rect.size), variant.src_rect, modulate)
	canvas_item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

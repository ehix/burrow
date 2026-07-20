extends GutTest
## TileTextureVariant: deterministic per-tile crop + flip so adjacent
## tiles drawn from the same small source texture don't show pixel-
## identical content (root cause: draw_texture_rect(tile=true) always
## resets UV to a draw call's own rect origin -- see
## docs/superpowers/specs/2026-07-20-tile-texture-variation-design.md).
## Pure-function tests only, per this project's own established pattern
## for renderer logic (see MazeRenderer.wall_occludes_extent() etc.) --
## no scene tree needed.


func test_variant_for_is_deterministic_for_the_same_tile() -> void:
	var a := TileTextureVariant.variant_for(Vector2i(3, 4), Vector2(48, 48), Vector2(200, 200))
	var b := TileTextureVariant.variant_for(Vector2i(3, 4), Vector2(48, 48), Vector2(200, 200))

	assert_eq(a.src_rect, b.src_rect)
	assert_eq(a.flip_h, b.flip_h)
	assert_eq(a.flip_v, b.flip_v)


func test_variant_for_differs_across_a_sample_of_tiles() -> void:
	var seen_offsets := {}
	for x in range(6):
		for y in range(6):
			var v := TileTextureVariant.variant_for(Vector2i(x, y), Vector2(48, 48), Vector2(200, 200))
			seen_offsets[v.src_rect.position] = true

	assert_gt(seen_offsets.size(), 1, "a 6x6 sample of tiles should not all pick the identical crop offset")


func test_variant_for_never_exceeds_texture_bounds() -> void:
	for x in range(10):
		for y in range(10):
			var v: Dictionary = TileTextureVariant.variant_for(Vector2i(x, y), Vector2(48, 16), Vector2(80, 71))
			assert_true(v.src_rect.position.x >= 0 and v.src_rect.position.y >= 0,
				"crop offset must never be negative (GDScript's %% keeps the dividend's sign on negative hashes)")
			assert_true(v.src_rect.position.x + v.src_rect.size.x <= 80,
				"crop must never sample past the texture's own width")
			assert_true(v.src_rect.position.y + v.src_rect.size.y <= 71,
				"crop must never sample past the texture's own height")


func test_variant_for_clamps_to_zero_offset_when_texture_is_smaller_than_dest() -> void:
	var v := TileTextureVariant.variant_for(Vector2i(7, 7), Vector2(48, 48), Vector2(20, 20))

	assert_eq(v.src_rect.position, Vector2(0, 0))
	assert_eq(v.src_rect.size, Vector2(48, 48))

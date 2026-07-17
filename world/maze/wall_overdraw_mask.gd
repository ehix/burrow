class_name WallOverdrawMask
extends Node2D
## Makes a wall's overdraw silhouette actually occlude an entity standing in
## the tile it pokes into (tunnel visual rework Phase 2 follow-up, playtest
## finding: Level.tscn's sibling draw order means Entities always paints
## over Renderer's walls regardless of the wall's own overdraw band, so a
## spider or Centipede standing right where a wall's fake-3D height should
## hide it instead renders fully on top, undermining the depth illusion --
## see docs/superpowers/specs/2026-07-14-tunnel-visual-rework-design.md's
## Phase 1 review notes for the same gap first flagged and deferred there).
##
## Rather than restructure wall rendering into per-tile Y-sorted nodes (a
## much bigger change), this repaints just the specific overdraw patches
## that currently overlap an occludable entity, as a final pass added AFTER
## Entities in Level.tscn -- so the patch simply paints over the entity's
## sprite a second time, using the exact same rect/alpha MazeRenderer itself
## is currently drawing there (MazeRenderer.overdraw_alpha_for()). Every
## occludable entity gets this same repaint, the player included, with no
## per-entity special case: how visible a given wall tile's overdraw is
## depends only on that tile's own distance from MazeRenderer's fade centre
## (normally the player's own tile, see MazeRenderer.set_fade_center()), not
## on which entity happens to be standing in it. That's what actually
## resolves the playtest ask ("occlude the player too, but don't make it
## hard to see") without a player/enemy double standard: walls right around
## the viewer fade toward transparent, walls anywhere else on the map stay
## fully solid, and any entity -- player or otherwise -- standing in a
## faded wall's overdraw gets repainted at that exact same live alpha.
## (Earlier versions tried this as an entity-type check here instead --
## skip the player entirely, then a flat translucent alpha for the player
## only -- both of which left every *other* wall on the map fully opaque
## regardless of how close the player actually was to it, an inconsistency
## that had nothing to do with the entity standing there.)

## See MazeRenderer.ENTITY_VISUAL_HALF_EXTENT's own doc comment.
const ENTITY_VISUAL_HALF_EXTENT := MazeRenderer.ENTITY_VISUAL_HALF_EXTENT

var _level: Level
var _renderer: MazeRenderer


func _ready() -> void:
	# Never relit by the player's VisionLight -- must always paint the exact
	# same literal color MazeRenderer's own wall draw would show at that
	# tile, or the two would visibly disagree at the fade edge. See
	# MazeRenderer._ready()'s own doc comment for the full playtest finding
	# this fixes.
	material = CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED


func setup(level: Level, renderer: MazeRenderer) -> void:
	_level = level
	_renderer = renderer
	set_process(not Engine.is_editor_hint())


func _process(_delta: float) -> void:
	queue_redraw()


## The wall tile whose overdraw could possibly cover `entity_tile`, given
## which plane is active -- ground walls poke into the tile north of them,
## ceiling walls into the tile south (see MazeRenderer's own _draw_wall_
## ground()/_draw_wall_ceiling() doc comments). A pure function so it's
## directly unit-testable without a scene tree.
static func wall_tile_for(entity_tile: Vector2i, plane: Level.Layer) -> Vector2i:
	if plane == Level.Layer.GROUND:
		return Vector2i(entity_tile.x, entity_tile.y + 1)
	return Vector2i(entity_tile.x, entity_tile.y - 1)


func _draw() -> void:
	if _level == null or _renderer == null or _level.maze == null:
		return
	var colors := _occluded_wall_tile_colors()
	for wall_tile in colors:
		draw_rect(_renderer.overdraw_rect_for(wall_tile), colors[wall_tile])


## Every wall tile currently occluding at least one entity, mapped to the
## color its repaint should use -- pure computation split out of _draw() so
## it's directly unit-testable. Several entities/columns can share one
## occluding wall tile; the color for a given tile depends only on the
## tile's own position (via _paint_color_for()), never on which entity
## triggered it, so every entity sharing a tile always agrees on its color
## and dedup here is just "skip a tile once it's already been computed."
##
## Playtest finding: _straddled_columns() deliberately checks an entity's
## own column AND one neighbor even for an entity resting dead-centre in its
## tile (see that function's own doc comment -- "a deliberate, harmless
## redundancy"). That redundancy stops being harmless the moment the
## neighbor column's wall_tile has ANOTHER wall stacked on the far side of
## it: this repaint would still fire for it (the straddle/extent checks
## above only look at the ENTITY's geometry, not at whether wall_tile's own
## sliver represents real occludable space), and since this repaint runs
## after Entities -- after MazeRenderer has already resolved that same rect
## in the stacked wall's own front-face cap's favor within its own _draw()
## call -- it would silently overwrite that cap with this wall_tile's own
## sliver color instead. MazeRenderer.poked_into_tile_is_open() is the same
## guard overdraw_alpha_for() uses to stop fading a seam like this; here it
## has to be a hard skip instead of just an alpha of 1.0, because painting
## ANYTHING here -- at any alpha -- is wrong when the poked-into tile isn't
## real occludable floor.
func _occluded_wall_tile_colors() -> Dictionary:
	var maze := _level.maze
	var plane := _renderer.active_plane()
	var overdraw := _renderer.wall_overdraw_height
	var colors := {}
	for entity in _occludable_entities():
		var position: Vector2 = entity.global_position
		var entity_tile := _level.tile_of(position)
		var base_wall_tile := wall_tile_for(entity_tile, plane)
		for col in _straddled_columns(position.x, ENTITY_VISUAL_HALF_EXTENT, Level.TILE_SIZE):
			var wall_tile := Vector2i(col, base_wall_tile.y)
			if colors.has(wall_tile):
				continue
			if maze.is_open(wall_tile.x, wall_tile.y):
				continue # no wall there -- nothing to occlude with
			if not _renderer.poked_into_tile_is_open(wall_tile):
				continue # this sliver is an internal wall-to-wall seam, not real occludable space
			var occludes := (
				MazeRenderer.wall_occludes_extent(wall_tile, position, ENTITY_VISUAL_HALF_EXTENT, Level.TILE_SIZE, overdraw)
				if plane == Level.Layer.GROUND
				else MazeRenderer.wall_occludes_extent_ceiling(wall_tile, position, ENTITY_VISUAL_HALF_EXTENT, Level.TILE_SIZE, overdraw)
			)
			if not occludes:
				continue
			colors[wall_tile] = _paint_color_for(wall_tile)
	return colors


## The repaint's own color for `wall_tile` -- wall_top_face_color at
## MazeRenderer's own live alpha for that tile (MazeRenderer.overdraw_
## alpha_for()), so the repaint over an entity's sprite never disagrees with
## what the wall itself is currently rendering there (see this class's own
## doc comment).
func _paint_color_for(wall_tile: Vector2i) -> Color:
	var color := _renderer.wall_top_face_color
	return Color(color, color.a * _renderer.overdraw_alpha_for(wall_tile))


## Every wall-tile x-column an entity's sprite could visually overlap at
## `position_x`, given its horizontal half-extent -- almost always both its
## own column and one neighbor while it's mid-step, since half_extent is
## close to half a tile wide. A pure function so it's directly unit-testable.
## Needed because entity_tile.x alone (a single floor-divided column) only
## ever names ONE candidate wall tile per frame; as an entity crosses a
## column boundary next to a wall run, checking only that one candidate left
## the far half of its sprite fully visible until the exact frame the column
## flipped, then reversed -- a hard "torn" pop every single tile crossing
## (playtest: "glitchy" walking behind a run of walls). Checking both
## candidates each frame, and letting wall_occludes_extent's own x-margin
## decide which (if either) genuinely still overlaps, fixes that without
## needing any cross-fade.
static func _straddled_columns(position_x: float, half_extent: float, tile_size: int) -> Array[int]:
	var left_col := int(floor((position_x - half_extent) / tile_size))
	var right_col := int(floor((position_x + half_extent) / tile_size))
	if left_col == right_col:
		return [left_col]
	return [left_col, right_col]


## Every entity that should be subject to wall-overdraw occlusion: the full
## "spiders" group (Player/Enemy/Decoy), every visual segment of every live
## Centipede/CentipedeExpressRider (their segments carry the actual
## position, not the body's own root node), and every live Blockade. The
## player is included like everyone else -- see this class's own doc
## comment for why occlusion no longer special-cases the player at all.
##
## Blockade playtest finding: it's parented under Entities exactly like
## Player/Enemy/Centipede segments (BlockadeSkill._spawn_parent() -- same
## sibling-draw-order gap this whole class exists to close), so a blockade
## standing in a wall's overdraw band was never reliably repainted the same
## way -- only "by accident" on a tick some OTHER entity's own straddle also
## happened to claim that exact wall_tile, since the paint dict dedupes per
## tile, not per entity. Registering it here directly is what actually
## guarantees it, matching every other occludable entity instead of leaving
## it to chance.
func _occludable_entities() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("spiders"):
		var spider := node as Node2D
		if spider != null:
			result.append(spider)
	for node in get_tree().get_nodes_in_group("centipedes"):
		var centipede := node as Centipede
		if centipede != null:
			for segment in centipede.get_segments():
				result.append(segment)
	for node in get_tree().get_nodes_in_group("centipede_express_riders"):
		var rider := node as CentipedeExpressRider
		if rider != null:
			for segment in rider.get_segments():
				result.append(segment)
	for node in get_tree().get_nodes_in_group("blockades"):
		var blockade := node as Node2D
		if blockade != null:
			result.append(blockade)
	return result

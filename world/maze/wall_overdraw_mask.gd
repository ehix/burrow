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
## sprite a second time, using the exact same rect/color MazeRenderer itself
## would draw there. Every occludable entity gets this same repaint,
## including the player now (playtest follow-up: the player used to be
## skipped entirely here, relying instead on MazeRenderer fading the wall's
## own paint underneath -- but that meant the player was never actually
## covered by the wall's silhouette the way an Enemy or Centipede segment
## is, just standing in front of a paler wall, a visibly different and
## inconsistent treatment). See _paint_color_for() for how the player still
## avoids ever being FULLY hidden -- a lower, translucent paint alpha
## instead of skipping the repaint altogether.

## See MazeRenderer.ENTITY_VISUAL_HALF_EXTENT's own doc comment.
const ENTITY_VISUAL_HALF_EXTENT := MazeRenderer.ENTITY_VISUAL_HALF_EXTENT

## The player's own repaint alpha -- translucent rather than the full
## wall_top_face_color opacity every other entity gets (see
## _paint_color_for()), so the player reads as genuinely behind the wall's
## silhouette (consistent draw-order/layering with every other entity) while
## never fully disappearing the way an Enemy or Centipede segment can.
const PLAYER_PAINT_ALPHA := 0.25

var _level: Level
var _renderer: MazeRenderer


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
## occluding wall tile, and the rect painted for a given tile is the same
## regardless of which entity triggered it -- EXCEPT the player's own lower
## alpha (see _paint_color_for()). When more than one entity claims the same
## wall_tile, the more opaque color always wins here, not just whichever
## entity happened to be checked first: a wall tile genuinely occluding a
## full-opacity entity (Enemy/Centipede/Decoy segment) must still look fully
## occluded even if the player also straddles into that same tile's band
## nearby (playtest bug: a centipede segment's own wall overdraw would go
## nearly transparent -- inheriting the player's translucent alpha instead
## of its own full opacity -- whenever the player walked close enough to
## share that tile's occlusion check, even though the player's sprite was
## nowhere near the segment's own pixels). _occludable_entities() lists
## spiders (the player included) before centipede segments, so first-wins
## dedup silently picked the player's softer paint far more often than the
## doc comment here used to assume was "rare."
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
			if maze.is_open(wall_tile.x, wall_tile.y):
				continue # no wall there -- nothing to occlude with
			var occludes := (
				MazeRenderer.wall_occludes_extent(wall_tile, position, ENTITY_VISUAL_HALF_EXTENT, Level.TILE_SIZE, overdraw)
				if plane == Level.Layer.GROUND
				else MazeRenderer.wall_occludes_extent_ceiling(wall_tile, position, ENTITY_VISUAL_HALF_EXTENT, Level.TILE_SIZE, overdraw)
			)
			if not occludes:
				continue
			var color := _paint_color_for(entity)
			if not colors.has(wall_tile) or color.a > colors[wall_tile].a:
				colors[wall_tile] = color
	return colors


## The repaint's own color for `entity` -- full wall_top_face_color opacity
## for every entity except the player, who gets PLAYER_PAINT_ALPHA instead
## so their sprite still shows through the wall's silhouette rather than
## vanishing behind it outright (see this class's own doc comment).
func _paint_color_for(entity: Node2D) -> Color:
	var color := _renderer.wall_top_face_color
	if entity is Player:
		return Color(color, color.a * PLAYER_PAINT_ALPHA)
	return color


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
## "spiders" group (Player/Enemy/Decoy), plus every visual segment of every
## live Centipede/CentipedeExpressRider (their segments carry the actual
## position, not the body's own root node). The player is included like
## everyone else -- see _paint_color_for() for how it still avoids ever
## being fully hidden.
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
	return result

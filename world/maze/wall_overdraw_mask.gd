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
## would draw there. The player is deliberately never occluded this way
## (skipped entirely, see _occludable_entities()) -- MazeRenderer's own
## fade_focus_position mechanic already keeps a wall from hiding the
## player, and that should stay a hard guarantee, not a coin-flip against
## whichever entity happens to draw last.

## Assumed vertical half-extent of an occludable entity's visible sprite --
## every entity this mask handles (Player/Enemy ~41px sprite, CentipedeSegment
## ~40px collision box) is roughly tile-sized, so this is deliberately just
## half a tile rather than a per-type measurement. See wall_occludes_extent()'s
## own doc comment for why a plain position check can't substitute for this.
const ENTITY_VISUAL_HALF_EXTENT := 24.0

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
	var maze := _level.maze
	var plane := _renderer.active_plane()
	var overdraw := _renderer.wall_overdraw_height
	var painted := {} # dedupe: several entities can share one occluding wall tile
	for entity in _occludable_entities():
		var entity_tile := _level.tile_of(entity.global_position)
		var wall_tile := wall_tile_for(entity_tile, plane)
		if maze.is_open(wall_tile.x, wall_tile.y):
			continue # no wall there -- nothing to occlude with
		if painted.has(wall_tile):
			continue
		var occludes := (
			MazeRenderer.wall_occludes_extent(wall_tile, entity.global_position, ENTITY_VISUAL_HALF_EXTENT, Level.TILE_SIZE, overdraw)
			if plane == Level.Layer.GROUND
			else MazeRenderer.wall_occludes_extent_ceiling(wall_tile, entity.global_position, ENTITY_VISUAL_HALF_EXTENT, Level.TILE_SIZE, overdraw)
		)
		if not occludes:
			continue
		painted[wall_tile] = true
		draw_rect(_renderer.overdraw_rect_for(wall_tile), _renderer.wall_top_face_color)


## Every entity that should be subject to wall-overdraw occlusion: the
## "spiders" group (Player/Enemy/Decoy) minus the player, plus every visual
## segment of every live Centipede/CentipedeExpressRider (their segments
## carry the actual position, not the body's own root node).
func _occludable_entities() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("spiders"):
		if node is Player:
			continue
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

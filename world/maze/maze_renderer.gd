class_name MazeRenderer
extends Node2D
## Draws a MazeData as flat floor rectangles and taller, two-tone wall
## blocks (tunnel faux-3D rework, design: docs/superpowers/specs/
## 2026-07-14-tunnel-visual-rework-design.md). A wall's rendered block is
## taller than its own 48x48 footprint -- a lighter "top face" plus a
## shorter, darker "front face" anchored to the tile's own bottom edge,
## with the extra height poking up into the tile north of it -- rather
## than a single flat-color rect, so walls read as physically standing at
## floor level instead of the old point-light shadow artifact that made
## them look unnaturally (and accidentally) tall. Placeholder colors/
## proportions, not real tile art yet -- swap for a TileMapLayer once
## SpriteCook art exists; the collision/occluder/navigation pipeline is
## built separately by Level, so it's unaffected either way.
##
## Tunnel visual rework Phase 2: floor rendering (including the old
## per-plane ceiling_floor_color recolor) has moved to FloorRenderer/
## GroundLayer, which reads "which plane am I on" via dimming instead of a
## color swap -- see docs/superpowers/specs/2026-07-14-tunnel-visual-
## rework-design.md. This class now draws walls only. set_active_plane()
## still drives which way a wall's front face renders (_draw_wall_ground()
## vs _draw_wall_ceiling()).

var _maze: MazeData
var _tile_size := 48
var wall_top_face_color := Color(0.36, 0.31, 0.26)
var wall_front_face_color := Color(0.2, 0.16, 0.12)
## Grid lines on top of open floor tiles, so the tile-stepped movement reads
## clearly against the map.
var grid_line_color := Color(1, 1, 1, 0.08)

## How far a wall's rendered block pokes up above its own tile's top edge,
## and the height of the darker front-face band anchored to its own bottom
## edge -- see this file's own doc comment. Placeholder proportions, easy
## to retune once real tile art exists.
var wall_overdraw_height := 16.0
var wall_front_face_height := 16.0

## How many tile-columns either side of the fade centre (see set_fade_
## center()) a wall's overdraw sliver softens, and how transparent it gets
## there -- see overdraw_alpha_for()'s own doc comment for why this is a
## flat window rather than a radius, and only ever touches the sliver, never
## the rest of the wall block. Placeholder numbers, easy to retune once real
## tile art exists (see this file's own doc comment).
var wall_fade_span_tiles := 1
var wall_fade_min_alpha := 0.25

var _active_plane: Level.Layer = Level.Layer.GROUND
var _fade_center_tile: Vector2i
var _has_fade_center := false

## Assumed visual half-extent (both axes) of an occludable entity's sprite --
## every entity this half-extent is used for (Player/Enemy ~41px sprite,
## CentipedeSegment ~40px collision box) is roughly tile-sized, so this is
## deliberately just half a tile rather than a per-type measurement. Lives
## here (not on WallOverdrawMask, its only reader) purely so wall_occludes_
## extent()/_ceiling() can sit next to the plain position-check functions
## they replace. See wall_occludes_extent()'s own doc comment for why a
## plain position check can't substitute for this.
const ENTITY_VISUAL_HALF_EXTENT := 24.0


func _ready() -> void:
	set_process(not Engine.is_editor_hint())
	# Walls always render at their own literal authored color, never relit by
	# the player's VisionLight (playtest finding: the light's real radial
	# falloff + real shadow-casting off each wall's LightOccluder2D was
	# recompositing every wall pixel -- including the overdraw fade band --
	# after this class had already drawn it, so two tiles painted with the
	# exact same alpha could still read as very different brightnesses, and
	# flickered as the light moved continuously while the fade window only
	# updates in whole-tile steps. This was always true of every solid wall
	# on the map, just invisible at full opacity; the translucent fade band
	# made it obvious because most of what shows through it is the
	# (differently-lit) floor beneath. WallOverdrawMask gets the identical
	# treatment for the same reason -- see its own _ready().)
	material = CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED


func _process(_delta: float) -> void:
	queue_redraw()


func setup(maze: MazeData, tile_size: int) -> void:
	_maze = maze
	_tile_size = tile_size
	queue_redraw()


## Which plane's floor color open tiles should currently draw in — the
## player's own plane (there's one camera, one local viewer).
func set_active_plane(plane: Level.Layer) -> void:
	_active_plane = plane
	queue_redraw()


## Read-only access to which plane is currently active -- WallOverdrawMask
## needs this to know which neighbor direction (north for ground, south for
## ceiling) a given entity's own wall-adjacency check should use.
func active_plane() -> Level.Layer:
	return _active_plane


## Where "the viewer" currently is, in tile coordinates -- Level calls this
## every frame with the player's own tile (mirrors the old fade_focus_
## position idiom, see _draw_wall_ground()'s doc comment for why that
## version was replaced). Drives overdraw_alpha_for(): the handful of wall
## tiles that could actually be occluding this tile right now soften toward
## transparent, so a wall about to swallow the player's own sprite doesn't
## actually hide it (the playtest ask this restores), while every other wall
## on the map -- including ones further along the very same wall run --
## stays fully solid.
func set_fade_center(tile: Vector2i) -> void:
	_fade_center_tile = tile
	_has_fade_center = true


## Alpha multiplier for a wall's overdraw sliver, given how many tile-
## columns it is from the fade centre's own column (`column_offset`, signed:
## negative is west, positive is east) -- `min_alpha` for every column
## within `span` tiles either side (inclusive), 1.0 (fully solid, matching
## every other wall on the map) beyond that. A pure function so it's
## directly unit-testable; see overdraw_alpha_for() for the wrapper that
## supplies the live `column_offset` from this renderer's own fade centre.
##
## Deliberately a flat step across the whole span, not a gradient: an
## earlier version faded gradually by radial (Chebyshev) tile-distance, but
## that meant two things at once: it reached tiles diagonally/vertically
## off from the fade centre that were never actually in the same overdraw
## row to begin with (the fade zone read as far larger than the handful of
## tiles that could ever visually matter), and as the player moved, tiles
## already inside the fade radius kept ramping toward different alpha
## values than tiles that had just entered it -- neighbouring tiles never
## agreeing on how transparent they should be at any given instant, reading
## as a flicker rather than a smooth fade (playtest finding). A uniform
## alpha across a narrow, row-correct span fixes both: only tiles that can
## actually occlude something near the viewer ever fade, and every one of
## them always reads exactly the same regardless of how long it's been in
## range.
static func overdraw_alpha_for_offset(column_offset: int, span: int, min_alpha: float) -> float:
	if absi(column_offset) <= span:
		return min_alpha
	return 1.0


## True if `wall_tile`'s sliver actually pokes into open floor -- the tile
## north of it on GROUND, south on CEILING -- rather than into ANOTHER wall.
## Only open floor can ever hold an entity worth occluding; when the poked-
## into tile is itself a wall, that sliver's rect is purely an internal
## rendering seam (see _draw_wall_ground()'s doc comment for the exact
## geometry) and must never be painted over independently of whatever
## that OTHER wall drew there -- see both this function's callers for the
## two distinct ways getting that wrong is visible (overdraw_alpha_for()'s
## own doc comment for the fade case, WallOverdrawMask._occluded_wall_tile_
## colors() for the repaint case). Live against the current maze every
## frame, not a one-time decision, so the instant an adjacent wall actually
## opens up (Remove Wall, Seismic Compaction, Centipede Express), this
## sliver starts being treated as real occludable space immediately.
func poked_into_tile_is_open(wall_tile: Vector2i) -> bool:
	var poked_into := (
		Vector2i(wall_tile.x, wall_tile.y - 1) if _active_plane == Level.Layer.GROUND
		else Vector2i(wall_tile.x, wall_tile.y + 1)
	)
	return _maze != null and _maze.is_open(poked_into.x, poked_into.y)


## Live alpha for `wall_tile`'s overdraw sliver right now -- 1.0 (no fade
## centre set yet, e.g. before Level's first _process()) unless `wall_tile`
## sits in the one row that could actually be occluding the fade centre's
## own tile (south of it on GROUND, north on CEILING -- the same row
## WallOverdrawMask.wall_tile_for() computes), in which case it's
## overdraw_alpha_for_offset() keyed off how many columns it is from the
## fade centre. _draw_wall_ground()/_draw_wall_ceiling() use this for the
## sliver only (never the front face or a wall's own-tile top face -- see
## their own doc comments for why just the sliver), and WallOverdrawMask's
## repaint pass calls this same function so a wall fading near the viewer
## and its repaint-over-an-entity pass never disagree about how transparent
## that tile currently is.
##
## Never fades when poked_into_tile_is_open(wall_tile) is false (playtest
## finding: two wall tiles stacked back-to-back share a seam exactly where
## the southern one's sliver overdraws the northern one's front face -- see
## _draw_wall_ground()'s doc comment for why that overlap exists and is
## normally invisible, both being drawn at full opacity in the same
## wall_top_face_color. Fading only the southern tile's sliver there, just
## because it happened to fall within the fade window, broke that -- it
## blended a translucent copy of the lighter top-face color over the darker
## front-face color underneath instead of leaving it fully covered,
## producing a visible seam/gap *inside* what should read as one continuous
## wall run, popping in and out as the player walked past).
func overdraw_alpha_for(wall_tile: Vector2i) -> float:
	if not _has_fade_center:
		return 1.0
	if not poked_into_tile_is_open(wall_tile):
		return 1.0
	var fade_row := _fade_center_tile.y + 1 if _active_plane == Level.Layer.GROUND else _fade_center_tile.y - 1
	if wall_tile.y != fade_row:
		return 1.0
	return overdraw_alpha_for_offset(wall_tile.x - _fade_center_tile.x, wall_fade_span_tiles, wall_fade_min_alpha)


## The overdraw sliver's own rect in world space for `tile` (a wall tile),
## matching whichever plane is currently active -- the exact patch
## _draw_wall_ground()/_draw_wall_ceiling() paints (at overdraw_alpha_for()'s
## live alpha) for that wall's top face poking into its neighbor.
## WallOverdrawMask paints this same patch again, on top of Entities,
## whenever an occludable entity is standing inside it, at that same live
## alpha -- see WallOverdrawMask's own doc comment for why a second pass is
## needed instead of just relying on draw order once.
func overdraw_rect_for(tile: Vector2i) -> Rect2:
	var tile_left := float(tile.x) * _tile_size
	if _active_plane == Level.Layer.GROUND:
		var tile_top := float(tile.y) * _tile_size
		return Rect2(tile_left, tile_top - wall_overdraw_height, _tile_size, wall_overdraw_height)
	else:
		var tile_bottom := float(tile.y) * _tile_size + _tile_size
		return Rect2(tile_left, tile_bottom, _tile_size, wall_overdraw_height)


func _draw() -> void:
	if _maze == null:
		return
	for y in _maze.height:
		for x in _maze.width:
			if not _maze.is_open(x, y):
				_draw_wall(Vector2i(x, y))
	_draw_grid_lines()


## Draws one wall tile's block, dispatching to the plane-appropriate
## orientation -- see _draw_wall_ground()/_draw_wall_ceiling().
func _draw_wall(tile: Vector2i) -> void:
	if _active_plane == Level.Layer.GROUND:
		_draw_wall_ground(tile)
	else:
		_draw_wall_ceiling(tile)


## Ground-plane wall: front face anchored to the tile's own bottom edge, top
## face poking up into the tile north of it. Front face and the wall's own-
## tile top face always render at full height and full opacity -- only the
## overdraw sliver itself (the bit poking into the neighboring tile, drawn
## separately here at overdraw_alpha_for()'s live alpha) ever fades, so a
## wall still reads as a solid physical block everywhere on the map; it's
## specifically the "reaches into the next tile and could swallow whatever's
## standing there" portion that softens near the viewer (see set_fade_
## center()'s doc comment). WallOverdrawMask repaints this same sliver, at
## this same alpha, on top of Entities -- see its own doc comment for why a
## second pass is needed instead of just relying on draw order once.
## (An earlier version faded the *entire* top-face rect here uniformly,
## driven by a fade_focus_position Level set to the player's position every
## frame -- replaced in favor of WallOverdrawMask handling fading entirely
## via a per-entity alpha, which was itself replaced by this tile-position-
## based version: entity-type special-casing meant only the player's own
## silhouette ever looked softened, leaving every other wall -- including
## ones right next to the player that just happened to have an Enemy or
## Centipede segment standing in them instead -- fully opaque, an
## inconsistent look the player/enemy distinction shouldn't be driving.)
## Always renders at full height even when a pit or flooded tile (same
## MazeData overlay -- see MazeData.is_pit()) sits in the tile north of it
## (playtest fix, mirrors _draw_wall_ceiling()): the overdraw represents
## the wall's own height occluding whatever's behind it from the viewer's
## perspective, and a hole is no exception to that -- its near edge should
## partially disappear behind the wall's silhouette, not the wall shrinking
## to avoid touching it. An earlier version clipped the overdraw to 0 next
## to a pit; that produced a visible notch in the wall's own silhouette
## right where a consistent block was expected, which is a worse look than
## the wall simply doing what it does everywhere else.
func _draw_wall_ground(tile: Vector2i) -> void:
	var tile_left := tile.x * _tile_size
	var tile_top := tile.y * _tile_size
	var tile_bottom := tile_top + _tile_size
	var front_face_top := tile_bottom - wall_front_face_height
	var overdraw_rect := overdraw_rect_for(tile)
	var own_top_face := Rect2(tile_left, tile_top, _tile_size, front_face_top - tile_top)
	draw_rect(overdraw_rect, Color(wall_top_face_color, wall_top_face_color.a * overdraw_alpha_for(tile)))
	draw_rect(own_top_face, wall_top_face_color)
	draw_rect(Rect2(tile_left, front_face_top, _tile_size, wall_front_face_height), wall_front_face_color)


## Ceiling-plane wall: mirrored -- front face anchored to the tile's own
## top edge, hanging down; top face pokes down into the tile south of it
## (tunnel visual rework Phase 2). Same "only the overdraw sliver fades"
## behavior as _draw_wall_ground() -- see its doc comment for both the
## pit/flooded-neighbor rationale and the fading design.
func _draw_wall_ceiling(tile: Vector2i) -> void:
	var tile_left := tile.x * _tile_size
	var tile_top := tile.y * _tile_size
	var tile_bottom := tile_top + _tile_size
	var front_face_bottom := tile_top + wall_front_face_height
	var overdraw_rect := overdraw_rect_for(tile)
	var own_top_face := Rect2(tile_left, front_face_bottom, _tile_size, tile_bottom - front_face_bottom)
	draw_rect(own_top_face, wall_top_face_color)
	draw_rect(overdraw_rect, Color(wall_top_face_color, wall_top_face_color.a * overdraw_alpha_for(tile)))
	draw_rect(Rect2(tile_left, tile_top, _tile_size, wall_front_face_height), wall_front_face_color)


## True if a wall at `wall_tile` (tile coordinates) would visually overlap
## `position` (world-space) given its rendered block pokes `overdraw`
## pixels above its own tile into the tile north of it -- anything
## standing in that northern sliver would otherwise be hidden behind the
## wall's own rendered height. A pure function (no scene tree needed) so
## it's directly unit-testable -- see docs/superpowers/specs/2026-07-14-
## tunnel-visual-rework-design.md.
static func wall_occludes_position(wall_tile: Vector2i, position: Vector2, tile_size: int, overdraw: float) -> bool:
	var tile_left := float(wall_tile.x) * tile_size
	var tile_top := float(wall_tile.y) * tile_size
	if position.x < tile_left or position.x > tile_left + tile_size:
		return false
	return position.y >= tile_top - overdraw and position.y <= tile_top


## Ceiling-plane mirror of wall_occludes_position(): the ceiling variant's
## rendered block pokes `overdraw` pixels below its own tile into the tile
## south of it (front face hangs down instead of rising up -- see
## _draw_wall_ceiling()) -- same occlusion idiom, opposite direction.
static func wall_occludes_position_ceiling(wall_tile: Vector2i, position: Vector2, tile_size: int, overdraw: float) -> bool:
	var tile_left := float(wall_tile.x) * tile_size
	var tile_bottom := float(wall_tile.y) * tile_size + tile_size
	if position.x < tile_left or position.x > tile_left + tile_size:
		return false
	return position.y >= tile_bottom and position.y <= tile_bottom + overdraw


## Size-aware sibling of wall_occludes_position(): true if an entity centred
## at `position` with half-extent `half_extent` (applied on BOTH axes) would
## visually overlap the overdraw band, not just its exact centre point.
## Needed on the y axis because GridMover always rests an entity at its own
## tile's centre -- 24px from any tile edge at this project's 48px tile
## size -- while the overdraw band is only ~16px deep, so a plain point
## check (wall_occludes_position) can never be true for a resting entity
## even though its actual sprite (roughly tile-sized, ~40-48px) visibly
## reaches within a few pixels of the edge either way. Found via playtest:
## WallOverdrawMask using the point check meant it essentially never fired
## in normal play -- entities always rested just outside the checked band
## while still visibly overlapping the wall's rendered overdraw. Needed on
## the x axis too (second playtest finding) so a moving entity whose sprite
## currently straddles a tile-column boundary -- true for most of every
## step, since half_extent is close to half a tile wide -- is still
## detected against a wall_tile candidate its exact centre x hasn't reached
## yet; the caller (WallOverdrawMask._draw()) is what actually supplies
## both neighboring wall_tile candidates to check this against, this
## function just has to stop rejecting the genuinely-overlapping one on x
## alone. Without this, an entity crossing a column boundary next to a wall
## run showed only half its sprite occluded for stretches of every step --
## the near half correctly hidden, the far half popping fully visible until
## the tile-column flip, then instantly reversing.
static func wall_occludes_extent(wall_tile: Vector2i, position: Vector2, half_extent: float, tile_size: int, overdraw: float) -> bool:
	var tile_left := float(wall_tile.x) * tile_size
	var tile_top := float(wall_tile.y) * tile_size
	if position.x + half_extent < tile_left or position.x - half_extent > tile_left + tile_size:
		return false
	return position.y + half_extent >= tile_top - overdraw and position.y - half_extent <= tile_top


## Ceiling-plane mirror of wall_occludes_extent() -- see its own doc comment.
static func wall_occludes_extent_ceiling(wall_tile: Vector2i, position: Vector2, half_extent: float, tile_size: int, overdraw: float) -> bool:
	var tile_left := float(wall_tile.x) * tile_size
	var tile_bottom := float(wall_tile.y) * tile_size + tile_size
	if position.x + half_extent < tile_left or position.x - half_extent > tile_left + tile_size:
		return false
	return position.y - half_extent <= tile_bottom + overdraw and position.y + half_extent >= tile_bottom


func _draw_grid_lines() -> void:
	var width_px := _maze.width * _tile_size
	var height_px := _maze.height * _tile_size
	for x in (_maze.width + 1):
		var px := x * _tile_size
		draw_line(Vector2(px, 0), Vector2(px, height_px), grid_line_color)
	for y in (_maze.height + 1):
		var py := y * _tile_size
		draw_line(Vector2(0, py), Vector2(width_px, py), grid_line_color)

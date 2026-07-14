class_name Centipede
extends Node2D
## Multi-tile segmented obstacle creature (Centipede entity, sub-project H,
## replaces Earthworm): stationary and non-combatant while intact, blocking
## a corridor on BOTH ground and ceiling planes at once (see
## Level.is_blocked()) across `body_length` tiles. `_tiles` is the single
## source of truth for which tiles the body currently occupies (head first,
## `_tiles[0]`); CentipedeSegment children are pure visual/physical mirrors
## of it, repositioned whenever `_tiles` changes. Any combative hit --
## melee or web-shot, from Player or Enemy, landing on ANY segment -- adds
## to one shared `_hits` counter (mirrors Blockade's plain counter, not
## HealthComponent: this creature can't be killed, only driven off).

const SegmentScene := preload("res://entities/centipede/centipede_segment.tscn")

enum State { BLOCKING, FLEEING, RELOCATING }

@export var hits_to_flee: int = 4
@export var body_length: int = 4
@export var crawl_step_time: float = 0.35

var state: State = State.BLOCKING
var _tiles: Array[Vector2i] = []
var _hits := 0
var _level: Node
var _segments: Array[CentipedeSegment] = []
var _target: Vector2i
var _path: Array[Vector2i] = []
var _exit_direction := Vector2i.ZERO
var _exit_steps_remaining := 0


func _ready() -> void:
	add_to_group("centipedes")


func bind_level(level: Node) -> void:
	_level = level


## Lays out the body at `tiles` (head first) and (re)builds its segment
## visuals to match. Called right after instancing and bind_level(), by
## Level._seed_centipedes() (initial seeding) and CentipedeExpress (an apex
## centipede riding its own freshly-carved corridor). Claims each tile the
## same way a crawl step claims a new one -- destroying whatever's already
## there (larva, trap, item) -- so a body never materializes silently
## overlapping something instead of squashing/eating it.
func spawn_at(tiles: Array[Vector2i]) -> void:
	_tiles = tiles.duplicate()
	for segment in _segments:
		if is_instance_valid(segment):
			segment.queue_free()
	_segments.clear()
	for tile in _tiles:
		_level._destroy_occupants_at(tile)
		var segment: CentipedeSegment = SegmentScene.instantiate()
		add_child(segment)
		segment.global_position = _level.tile_centre(tile)
		_segments.append(segment)


## Any segment being hit lands here (CentipedeSegment.take_hit() forwards to
## its parent) -- one shared counter for the whole body. A no-op once
## already FLEEING/RELOCATING, mirroring Earthworm.take_hit()'s guard
## against re-triggering mid-retreat.
func take_hit() -> void:
	if state != State.BLOCKING:
		return
	_hits += 1
	if _hits >= hits_to_flee:
		_begin_flee()


## Melee's exact-tile lookup (Player/Enemy) only ever has the Centipede
## itself in hand (via segment_at_tile()), never the specific
## CentipedeSegment node WebShot's physics overlap already holds directly --
## this re-derives which segment sits at `tile` so a melee hit gets the same
## per-segment shunt CentipedeSegment.take_hit() gives a web-shot hit, then
## registers the hit exactly like take_hit() always has.
func hit_segment_at(tile: Vector2i, hit_direction: Vector2 = Vector2.ZERO) -> void:
	var idx := _tiles.find(tile)
	if idx != -1 and idx < _segments.size():
		CombatFx.shunt(_segments[idx], hit_direction * 5.0)
	take_hit()


func _begin_flee() -> void:
	state = State.FLEEING
	_target = _nearest_boundary_tile()
	_start_crawl()
	_schedule_next_step()


## The open, non-boundary tile closest to the current head that itself
## touches the map's boundary ring -- the nearest real "edge of the maze"
## the body can actually stand on and "burrow out" from. Deliberately NOT a
## literal boundary tile (x/y == 0 or width-1/height-1): MazeGenerator
## always leaves that outermost ring solid (MazeData.is_boundary()'s own
## doc comment), and _tunnel_toward() deliberately refuses to ever carve it
## (the same guardrail RemoveWallsSkill/SeismicCompaction honor) -- so a
## literal boundary tile is permanently unreachable by construction, which
## would leave FLEEING never able to arrive. Searches every open cell
## (not a fixed coordinate formula) because the tile directly "one step
## in" from the edge on the head's own row/column isn't itself guaranteed
## open -- only true cell-centres are guaranteed open, and which cells are
## boundary-adjacent depends on the generated maze, not a fixed offset.
func _nearest_boundary_tile() -> Vector2i:
	var head: Vector2i = _tiles[0]
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var best_tile: Vector2i = head
	var best_dist := INF
	for cell in _level.maze.open_cells():
		if _level.is_boundary(cell):
			continue
		var touches_boundary := false
		for dir in dirs:
			if _level.is_boundary(cell + dir):
				touches_boundary = true
				break
		if not touches_boundary:
			continue
		var dist := absi(cell.x - head.x) + absi(cell.y - head.y)
		if dist < best_dist:
			best_dist = dist
			best_tile = cell
	return best_tile


## Boxed-in fallback (design §6): if no open+dry path exists, carve the
## single adjacent non-boundary wall tile that most shortens the remaining
## distance to `target`, then retry. If even that finds no candidate (fully
## enclosed by the map boundary -- extremely unlikely), _path stays empty;
## _crawl_step()'s own empty-path branch retries this same search again
## next tick rather than freezing or falsely "arriving".
func _start_crawl() -> void:
	_path = _find_path(_tiles[0], _target)
	if _path.is_empty() and _tunnel_toward(_target):
		_path = _find_path(_tiles[0], _target)


## Finds the wall tile, adjacent to ANY tile currently reachable from the
## head (open, dry, not this body's own tiles -- the same criteria
## _find_path() itself walks), that minimizes remaining Manhattan distance
## to `target`, excluding any boundary tile from candidacy -- the same
## caller-side guardrail check RemoveWallsSkill/SeismicCompaction both
## perform before touching wall geometry (Level.dev_remove_wall_at() itself
## enforces no such restriction; it's the unrestricted dev cheat). Carves
## the chosen tile open. Returns false if no non-boundary wall candidate
## exists anywhere on the reachable pocket's boundary.
##
## Searching the whole reachable pocket -- not just the head's own 4
## neighbors -- matters: the head's own position never moves just from
## carving (only an actual _crawl_step() advances it), so a head-only
## search exhausts itself after at most 4 carves and then returns false
## forever, even though the tile it just carved may have its own wall
## neighbors leading further out. Found via stress-testing: a boxed-in
## centipede whose first carve opened onto a small dead-end pocket got
## stuck retrying indefinitely, since every later _start_crawl() call
## re-examined the exact same (now fully open-or-boundary) head neighbors.
func _tunnel_toward(target: Vector2i) -> bool:
	var head: Vector2i = _tiles[0]
	var occupied := {}
	for tile in _tiles:
		occupied[tile] = true
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var reachable := {head: true}
	var frontier: Array[Vector2i] = [head]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for dir in dirs:
			var next: Vector2i = current + dir
			if reachable.has(next) or occupied.has(next):
				continue
			if not _level.maze.is_open(next.x, next.y) or _level.is_water_at(next):
				continue
			reachable[next] = true
			frontier.append(next)
	var best_tile := Vector2i.ZERO
	var best_dist := INF
	var found := false
	for reached in reachable:
		for dir in dirs:
			var candidate: Vector2i = reached + dir
			if _level.is_boundary(candidate):
				continue
			if _level.maze.is_open(candidate.x, candidate.y):
				continue
			var dist := absi(candidate.x - target.x) + absi(candidate.y - target.y)
			if dist < best_dist:
				best_dist = dist
				best_tile = candidate
				found = true
	if not found:
		return false
	_level.dev_remove_wall_at(best_tile)
	return true


## Schedules one crawl tick crawl_step_time seconds from now, real-timer-
## paced like WaterIngress's own ring scheduling (not per-frame movement --
## this is a slow, deliberate crawl, not player-speed motion).
func _schedule_next_step() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(crawl_step_time).timeout.connect(_crawl_step)


func _crawl_step() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	if _path.is_empty():
		# Nowhere to go yet (e.g. still boxed in) -- retry the search next
		# tick rather than freezing or falsely "arriving".
		_start_crawl()
		_schedule_next_step()
		return
	if _path.size() == 1:
		_arrive()
		return
	var next_tile: Vector2i = _path[1]
	if not _level.maze.is_open(next_tile.x, next_tile.y) or _level.is_water_at(next_tile):
		# Something changed underfoot mid-crawl (e.g. a fresh flood) --
		# recompute from where we are now instead of stepping into it.
		_start_crawl()
		_schedule_next_step()
		return
	Centipede.shove_spiders_out_of(get_tree(), next_tile, next_tile - _tiles[0])
	_level._destroy_occupants_at(next_tile)
	_tiles.push_front(next_tile)
	_tiles.pop_back()
	_sync_segments()
	_path.remove_at(0)
	if next_tile == _target:
		_arrive()
	else:
		_schedule_next_step()


## Any spider (Player/Enemy) currently standing on `tile` gets shoved out of
## it in `push_dir` before a crawling body's head moves there. Level.
## is_blocked() already stops a spider from stepping ONTO an occupied
## Centipede tile, but nothing stopped the body itself from crawling into a
## spider already standing there -- a strong physical boundary shouldn't
## ever overlap a spider, fleeing or not, so every crawl step clears its own
## way first. Reuses GridMover.knockback() (the same forced-shove primitive
## a landed combat hit already uses): tries straight along the body's own
## travel direction first, then falls back to the other three cardinal
## directions so a spider caught against a wall still gets bumped sideways
## onto open floor instead of getting walked through -- a genuine "rock and
## hard place" would need all four directions blocked simultaneously.
## Static so CentipedeExpressRider (Centipede Express's own transient,
## always-moving creature) can reuse the identical primitive without
## inheriting this obstacle-Centipede's BLOCKING/FLEEING/RELOCATING state
## machine, which doesn't apply to it at all.
static func shove_spiders_out_of(tree: SceneTree, tile: Vector2i, push_dir: Vector2i) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group("spiders"):
		var spider := node as Node2D
		if spider == null:
			continue
		var mover := spider.get_node_or_null("GridMover") as GridMover
		if mover == null or mover.committed_tile() != tile:
			continue
		if mover.knockback(push_dir):
			continue
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if dir != push_dir and mover.knockback(dir):
				break


func _arrive() -> void:
	if state == State.FLEEING:
		_begin_exit()
	elif state == State.RELOCATING:
		state = State.BLOCKING


## Once a FLEEING body's head reaches its boundary-adjacent target, it
## doesn't just vanish -- it keeps crawling straight out through the
## boundary ring for body_length + 1 more steps (the same push_front/
## pop_back mechanic every ordinary crawl step already uses), so the whole
## segmented body visibly recedes off the edge of the map tile-by-tile,
## exactly like it crawled in, instead of the entire node popping out of
## existence at once. body_length steps alone only brings the TAIL as far
## as the boundary ring tile itself -- still a solid, visibly-rendered
## wall block, not genuinely off-map -- so the tail would still appear to
## be sitting right at the edge the instant the node frees (found via
## playtest: it looked like it vanished a beat too early). The extra step
## carries the tail one tile past the ring too, into space that's never
## rendered at all.
func _begin_exit() -> void:
	_exit_direction = _direction_off_the_map(_tiles[0])
	_exit_steps_remaining = body_length + 1
	_schedule_next_exit_step()


## The direction from `tile` (assumed boundary-ring-adjacent -- exactly what
## _nearest_boundary_tile() picks) toward whichever neighboring boundary-ring
## tile it touches: "out of the map" from here.
func _direction_off_the_map(tile: Vector2i) -> Vector2i:
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if _level.is_boundary(tile + dir):
			return dir
	return Vector2i.ZERO


func _schedule_next_exit_step() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(crawl_step_time).timeout.connect(_exit_step)


## Continues the crawl straight through the boundary and off the map --
## deliberately skips every ordinary crawl guard (is_open/is_water/tunnel):
## past the target these tiles are the solid boundary ring and beyond, by
## design never carved or walkable, so treating them as ordinary crawl
## destinations would wrongly reroute or tunnel. `_exit_steps_remaining`
## counts down from body_length + 1; once it hits 0 the tail has cleared
## the boundary ring itself (not just reached it) and the whole body is
## genuinely off-map.
func _exit_step() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	_tiles.push_front(_tiles[0] + _exit_direction)
	_tiles.pop_back()
	_sync_segments()
	_exit_steps_remaining -= 1
	if _exit_steps_remaining <= 0:
		queue_free()
	else:
		_schedule_next_exit_step()


## Called by Level (via _flood_centipedes_at()) when a tile this body
## occupies just got flooded. A no-op unless currently BLOCKING -- already
## FLEEING/RELOCATING takes priority, mirrors take_hit()'s own guard.
func notify_flooded() -> void:
	if state != State.BLOCKING:
		return
	var destination := _pick_relocate_target()
	if destination == _tiles[0]:
		return # nowhere dry to go -- stay put, a later flood event will try again
	state = State.RELOCATING
	_target = destination
	_start_crawl()
	_schedule_next_step()


## A random open, dry, non-boundary tile not already part of this body --
## the crawl stepper naturally reforms the body as the tail of whatever
## path the head walks to reach it (snake-style), so this only needs to
## pick a single destination tile, not a pre-formed chain (unlike the
## initial spawn placement in Level._seed_centipedes(), which does need a
## pre-formed chain since there's no crawl to lay one out at spawn time).
## Returns the current head tile itself if nothing valid is found --
## notify_flooded() reads that as "stay put".
func _pick_relocate_target() -> Vector2i:
	var head: Vector2i = _tiles[0]
	var occupied := {}
	for tile in _tiles:
		occupied[tile] = true
	var candidates: Array[Vector2i] = _level.maze.open_cells().duplicate()
	candidates.shuffle()
	for candidate in candidates:
		if occupied.has(candidate):
			continue
		if _level.is_water_at(candidate):
			continue
		if _level.is_boundary(candidate):
			continue
		return candidate
	return head


func _sync_segments() -> void:
	for i in _segments.size():
		if i < _tiles.size():
			_segments[i].global_position = _level.tile_centre(_tiles[i])


## The live Centipede whose body occupies `tile`, or null. Mirrors
## Blockade.at_tile()'s shape but deliberately drops the `tile_size`
## parameter Blockade takes: Blockade only stores `global_position` and
## needs `tile_size` to convert it back to a tile coordinate for comparison,
## but Centipede already stores `_tiles` directly (the whole body's single
## source of truth), so no conversion is needed here.
static func segment_at_tile(tree: SceneTree, tile: Vector2i) -> Centipede:
	for node in tree.get_nodes_in_group("centipedes"):
		var centipede := node as Centipede
		if centipede == null:
			continue
		if tile in centipede._tiles:
			return centipede
	return null


## Local BFS from `from` to `to` (design §6): a tile is passable if it's
## open, not flooded, and not currently occupied by this body's own
## trailing tiles (so a crawl step never tries to path through itself).
## Deliberately separate from the shared Enemy/Player AStar (Level._astar/
## GridNav) -- that grid doesn't treat water as solid at all today, and
## Centipede's own pathing needs (reach a boundary tile, reach a fresh spot)
## are much simpler than Enemy's chase-a-moving-target. Returns [] if
## unreachable.
func _find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		return [from]
	var occupied := {}
	for tile in _tiles:
		occupied[tile] = true
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var came_from := {from: from}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == to:
			break
		for dir in dirs:
			var next: Vector2i = current + dir
			if came_from.has(next):
				continue
			if not _level.maze.is_open(next.x, next.y):
				continue
			if _level.is_water_at(next):
				continue
			if occupied.has(next):
				continue
			came_from[next] = current
			frontier.append(next)
	if not came_from.has(to):
		return []
	var path: Array[Vector2i] = [to]
	var walk: Vector2i = to
	while walk != from:
		walk = came_from[walk]
		path.append(walk)
	path.reverse()
	return path

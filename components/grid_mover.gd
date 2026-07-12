class_name GridMover
extends Node
## Animates its parent Node2D one grid tile at a time (4-directional). Used by
## the player, enemy and larva so they all step on the maze grid identically.
##
## Blocking is decided by `block_check` if set, else by the parent body's
## `test_move` — so entities never need the MazeData handed to them. Stepping
## maths live in tick(delta) so they can be unit-tested without physics frames.

signal step_finished

@export var tile_size: int = 48
@export var step_time: float = 0.12

## Multiplies step speed (1.0 = normal). The web slow drops this below 1.
var speed_scale: float = 1.0
## Optional `func(dir: Vector2i) -> bool` — return true to block a step. When
## unset, the parent PhysicsBody2D.test_move is used instead.
var block_check: Callable = Callable()

var _moving := false
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _elapsed := 0.0
var _buffered := Vector2i.ZERO
var _slow_gen := 0
## Seconds of stun remaining. While > 0 the owner cannot start a step (an
## in-flight step still finishes). Set by a landed hit to impede the victim.
var _stun_left := 0.0


func _ready() -> void:
	set_process(not Engine.is_editor_hint())


func _process(delta: float) -> void:
	tick(delta)


func _mover_node() -> Node2D:
	return get_parent() as Node2D


func is_moving() -> bool:
	return _moving


func is_stunned() -> bool:
	return _stun_left > 0.0


## The tile this mover currently owns: its landing tile if a step is in
## flight, else its current tile. Blocking checks must consult this — not just
## live physical overlap — or a step that was validly started toward an empty
## tile can still land on someone who arrives there (e.g. via knockback) after
## the step began, since a step's own blocking check only runs once, at start.
func committed_tile() -> Vector2i:
	var pos := _to if _moving else _mover_node().global_position
	var ts := float(tile_size)
	return Vector2i(int(floorf(pos.x / ts)), int(floorf(pos.y / ts)))


## True if stepping `dir` from `self_node` would land on a tile another spider
## already owns — occupied now, or already committed to via an in-flight step.
## Shared by Player and Enemy so spiders can't land on each other's tile.
## Ceiling/plane mechanics rework: only contests against a node on the same
## plane — a ground spider and a ceiling spider physically occupy different
## layers and never block each other's tile.
static func spider_tile_contested(mover: GridMover, self_node: Node2D, dir: Vector2i) -> bool:
	var target_pos := self_node.global_position + Vector2(dir) * float(mover.tile_size)
	var ts := float(mover.tile_size)
	var target_tile := Vector2i(int(floorf(target_pos.x / ts)), int(floorf(target_pos.y / ts)))
	for node in self_node.get_tree().get_nodes_in_group("spiders"):
		if node == self_node:
			continue
		var other := node as Node2D
		if other == null or not PlaneComponent.same_plane(self_node, other):
			continue
		var other_mover := other.get_node_or_null("GridMover") as GridMover
		if other_mover != null and other_mover.committed_tile() == target_tile:
			return true
	return false


## Begin a one-tile step in a cardinal direction. Buffers and returns false if
## already moving; returns false if stunned or blocked; true if a step started.
func try_step(dir: Vector2i) -> bool:
	if dir == Vector2i.ZERO:
		return false
	if _stun_left > 0.0:
		return false
	if _moving:
		_buffered = dir
		return false
	if _is_blocked(dir):
		return false
	_begin_step(dir)
	return true


## Force a one-tile shove in `dir`, bypassing stun (a hit lands even on a stunned
## victim). Ignored mid-step or into a wall/spider; returns whether it moved.
func knockback(dir: Vector2i) -> bool:
	if dir == Vector2i.ZERO or _moving or _is_blocked(dir):
		return false
	_buffered = Vector2i.ZERO # a shove cancels any queued input
	_begin_step(dir)
	return true


## Stop the owner acting for `duration` seconds (longest pending stun wins).
func stun(duration: float) -> void:
	_stun_left = maxf(_stun_left, duration)


## Drop any queued step. Callers whose input can be released mid-step (the
## player) must call this the instant input stops, or a step that finishes
## right after release will still auto-continue into a stale buffered
## direction (the "moves two tiles per tap" bug).
func cancel_buffer() -> void:
	_buffered = Vector2i.ZERO


## Halt any in-flight step immediately and drop the buffer. Callers that
## forcibly reposition the owner from outside the step animation (a trap
## snapping a caught larva to its centre) must call this, or tick() will keep
## lerping toward the pre-capture destination on the next frame and drag the
## owner right back off the position that was just set.
func stop() -> void:
	_moving = false
	_buffered = Vector2i.ZERO


func _begin_step(dir: Vector2i) -> void:
	var node := _mover_node()
	_from = node.global_position
	_to = _from + Vector2(dir) * float(tile_size)
	_elapsed = 0.0
	_moving = true


func _is_blocked(dir: Vector2i) -> bool:
	if block_check.is_valid():
		return block_check.call(dir)
	var body := get_parent() as PhysicsBody2D
	if body == null:
		return false
	return body.test_move(body.global_transform, Vector2(dir) * float(tile_size))


func tick(delta: float) -> void:
	if _stun_left > 0.0:
		_stun_left = maxf(0.0, _stun_left - delta)
	if not _moving:
		return
	_elapsed += delta * speed_scale
	var t := clampf(_elapsed / step_time, 0.0, 1.0)
	_mover_node().global_position = _from.lerp(_to, t)
	if t >= 1.0:
		_moving = false
		step_finished.emit()
		if _buffered != Vector2i.ZERO:
			var d := _buffered
			_buffered = Vector2i.ZERO
			try_step(d)


## Slow to `factor` of normal speed for `duration` seconds, then restore. A
## newer slow supersedes an older one — a stale timer will not reset an active
## slow (generation guard).
func apply_slow(factor: float, duration: float) -> void:
	speed_scale = factor
	if is_inside_tree():
		_slow_gen += 1
		var gen := _slow_gen
		get_tree().create_timer(duration).timeout.connect(
			func() -> void:
				if gen == _slow_gen:
					speed_scale = 1.0)

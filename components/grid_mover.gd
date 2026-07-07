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

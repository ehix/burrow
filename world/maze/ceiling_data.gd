class_name CeilingData
extends RefCounted
## The inverted floor plane directly above the ground maze (design §1: Dual-
## Plane Map Architecture). Shares the ground MazeData's wall geometry
## one-to-one — the same rock that blocks ground movement blocks the ceiling
## — but a ground pit never blocks it: a pit is a ground-elevation hazard, not
## a hole through solid rock overhead, so "ceiling travel bypasses pits"
## (spec's Traversability clause) falls out of `MazeData.is_open()` simply
## never being pit-aware, rather than needing its own tile data.

var ground: MazeData


func _init(ground_maze: MazeData) -> void:
	ground = ground_maze


func is_open(x: int, y: int) -> bool:
	return ground.is_open(x, y)


func is_blocked(x: int, y: int) -> bool:
	return not is_open(x, y)

class_name TileTypes
extends RefCounted
## Classifies a floor cell by which of its four cardinal neighbours are open.
## Salvaged concept from the Godot 3.x prototype's TileTypes.gd, reworked into a
## pure, testable function. Names describe the *walls* of the piece (e.g. a
## CORNER_BOTTOM_LEFT has walls on the left and bottom, so it opens up + right).
##
## Used for larva orientation and could later drive autotiling.

enum Type {
	BLOCKED_CELL,       ## no open neighbours (a wall, or an isolated cell)
	TUNNEL_HORIZONTAL,  ## left <-> right (also a horizontal dead-end)
	TUNNEL_VERTICAL,    ## up <-> down (also a vertical dead-end)
	CORNER_TOP_LEFT,    ## walls top+left; opens down + right
	CORNER_TOP_RIGHT,   ## walls top+right; opens down + left
	CORNER_BOTTOM_LEFT, ## walls bottom+left; opens up + right
	CORNER_BOTTOM_RIGHT,## walls bottom+right; opens up + left
	T_NORMAL,           ## bar on top; opens down+left+right
	T_UPSIDE_DOWN,      ## bar on bottom; opens up+left+right
	T_LEFT,             ## bar on left; opens up+down+right
	T_RIGHT,            ## bar on right; opens up+down+left
	CROSSROAD,          ## all four open
}


## Classify a cell from the openness of its up/right/down/left neighbours.
## A single-opening cell (dead-end) reads as the tunnel of that axis.
static func classify(up: bool, right: bool, down: bool, left: bool) -> Type:
	var count := int(up) + int(right) + int(down) + int(left)
	match count:
		0:
			return Type.BLOCKED_CELL
		1:
			return Type.TUNNEL_VERTICAL if (up or down) else Type.TUNNEL_HORIZONTAL
		2:
			if up and down:
				return Type.TUNNEL_VERTICAL
			if left and right:
				return Type.TUNNEL_HORIZONTAL
			if up and right:
				return Type.CORNER_BOTTOM_LEFT
			if up and left:
				return Type.CORNER_BOTTOM_RIGHT
			if down and right:
				return Type.CORNER_TOP_LEFT
			return Type.CORNER_TOP_RIGHT # down and left
		3:
			if not up:
				return Type.T_NORMAL       # bar on top
			if not down:
				return Type.T_UPSIDE_DOWN  # bar on bottom
			if not left:
				return Type.T_LEFT         # bar on left
			return Type.T_RIGHT            # bar on right (not right)
		_:
			return Type.CROSSROAD


## The direction a wandering larva should face when dropped onto a tile — it
## heads into the tunnel, away from any single wall. Mirrors the prototype's
## decide_orientation but derived directly from the classified type.
static func default_facing(type: Type) -> Vector2i:
	match type:
		Type.TUNNEL_VERTICAL, Type.CORNER_BOTTOM_LEFT, Type.CORNER_BOTTOM_RIGHT, \
		Type.T_UPSIDE_DOWN, Type.CROSSROAD:
			return Vector2i.UP
		Type.T_NORMAL, Type.CORNER_TOP_LEFT, Type.CORNER_TOP_RIGHT:
			return Vector2i.DOWN
		Type.TUNNEL_HORIZONTAL, Type.T_LEFT:
			return Vector2i.RIGHT
		Type.T_RIGHT:
			return Vector2i.LEFT
		_:
			return Vector2i.ZERO

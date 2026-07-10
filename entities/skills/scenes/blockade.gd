class_name Blockade
extends StaticBody2D
## Funnel/Weaver Spider's Blockade (design §3): a destructible rock/dirt
## barrier — unlike WebTrap (never blocks movement), this is a hard physical
## obstacle on the world layer until destroyed, so it blocks spiders via the
## existing test_move-based checks with zero changes to Player/Enemy's own
## collision masks. Placeholder visual: a solid drawn block, no art asset yet.
##
## Higher durability than a web trap (default 6 hits vs. WebTrap's 3) — see
## take_hit(), called from Player._melee and WebShot._on_body_entered.

var hits_to_destroy: int = 6
var _hits := 0


## Called by BlockadeSkill right after placement.
func setup(hits: int) -> void:
	hits_to_destroy = hits


## The live Blockade sitting on `tile`, or null. Returns the node (not just a
## bool) so a caller that needs to act on it (RemoveWallsSkill destroying it,
## Task 3) doesn't have to re-scan the group a second time.
static func at_tile(tree: SceneTree, tile: Vector2i, tile_size: int) -> Blockade:
	var ts := float(tile_size)
	for node in tree.get_nodes_in_group("blockades"):
		var blockade := node as Blockade
		if blockade == null:
			continue
		var blockade_tile := Vector2i(int(floorf(blockade.global_position.x / ts)), int(floorf(blockade.global_position.y / ts)))
		if blockade_tile == tile:
			return blockade
	return null


func _ready() -> void:
	add_to_group("blockades")


func _draw() -> void:
	var half := 20.0
	draw_rect(Rect2(Vector2(-half, -half), Vector2(half, half) * 2.0), Color(0.35, 0.25, 0.15, 0.95))


func take_hit() -> void:
	_hits += 1
	if _hits >= hits_to_destroy:
		queue_free()

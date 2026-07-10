class_name RemoveWallsSkill
extends SkillComponent
## General utility (design §4): high-hunger-cost player action that destroys
## the wall tile directly ahead of the source. UNLIKE World._dev_remove_wall
## (a debug cheat with no restriction, deliberately left as-is for dev/testing
## — see test_dev_remove_wall_carves_the_border_open), this is the
## production-facing path: guardrail — outer map-boundary tiles are hard-
## locked and never carved, even adjacent to them, via
## Level.is_boundary()/MazeData.is_boundary().

func _on_activate(source: Node) -> void:
	var mover := source as Node2D
	if mover == null:
		return
	var level := source.get_tree().get_first_node_in_group("level") as Level
	if level == null or level.maze == null:
		return
	var facing: Vector2 = source.get("facing") if "facing" in source else Vector2.RIGHT
	var target := level.tile_of(mover.global_position + facing * float(Level.TILE_SIZE))
	var blockade := Blockade.at_tile(source.get_tree(), target, Level.TILE_SIZE)
	if blockade != null:
		blockade.destroy()
		return
	if level.is_boundary(target):
		return  # guardrail: the outer wall can never be destroyed this way
	level.dev_remove_wall_at(target)  # same carve mechanism, boundary-gated here

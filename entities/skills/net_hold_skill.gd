class_name NetHoldSkill
extends SkillComponent
## Net-Casting Spider (male): "hold out a net" to instantly harvest a larva
## already caught in a web within reach — a melee-range shortcut on top of the
## normal walk-up-and-consume flow. Requires web contact per the class kit: a
## loose, uncaught larva is untouched (that's what the melee-focused kit's
## damage output is for).

@export var reach: float = 48.0


func _on_activate(source: Node) -> void:
	var trap := _nearest_ready_trap(source as Node2D)
	if trap != null:
		trap.try_consume(source)


func _nearest_ready_trap(source: Node2D) -> WebTrap:
	if source == null:
		return null
	var best: WebTrap = null
	var best_dist := reach
	for node in source.get_tree().get_nodes_in_group("traps"):
		var trap := node as WebTrap
		if trap == null or trap.caught_larva == null:
			continue
		var d := source.global_position.distance_to(trap.global_position)
		if d <= best_dist:
			best_dist = d
			best = trap
	return best

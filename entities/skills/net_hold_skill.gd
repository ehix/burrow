class_name NetHoldSkill
extends SkillComponent
## Net-Casting Spider: pick up a placed trap you own and hold it out ahead of
## you as a mobile hazard (design doc, Net-caster rework). Any larva that
## steps onto the held trap's forward tile is eaten immediately and the trap
## is spent. A pre-loaded trap (one that already caught a larva before being
## picked up) is eaten immediately on pickup instead. No manual drop —
## holding only ever resolves by eating (here) or by NetShotSkill firing it
## (spend()).

@export var reach: float = 48.0

var holding: bool = false

var _visual: Node2D = null
var _holder: Node2D = null


## Placeholder held-trap graphic, matching NetShot's own draw-a-diamond
## convention — swap for real art later.
class HeldTrapVisual:
	extends Node2D

	func _draw() -> void:
		var half := 8.0
		var pts := PackedVector2Array([Vector2(half, 0), Vector2(0, half), Vector2(-half, 0), Vector2(0, -half)])
		draw_colored_polygon(pts, Color(0.75, 0.75, 0.7, 0.85))
		draw_line(pts[0], pts[2], Color(0.4, 0.4, 0.35), 1.0)
		draw_line(pts[1], pts[3], Color(0.4, 0.4, 0.35), 1.0)


func _on_activate(source: Node) -> void:
	if holding:
		return
	var trap := _nearest_ready_trap(source as Node2D)
	if trap == null:
		return
	_holder = source as Node2D
	if trap.caught_larva != null:
		_eat(trap.caught_larva, source)
	trap.queue_free()
	holding = true
	_spawn_visual()


func is_holding() -> bool:
	return holding


## Called by NetShotSkill when it fires — ends holding without eating
## anything (the trap becomes the projectile instead).
func spend() -> void:
	holding = false
	_teardown_visual()


func _physics_process(_delta: float) -> void:
	if not holding or _holder == null or not is_instance_valid(_holder):
		return
	var forward := _forward_tile_position(_holder)
	if _visual != null and is_instance_valid(_visual):
		_visual.global_position = forward
	var catch_radius := _tile_size(_holder) * 0.5
	for node in _holder.get_tree().get_nodes_in_group("larvae"):
		var larva := node as Node2D
		if larva == null:
			continue
		if larva.global_position.distance_to(forward) <= catch_radius:
			_eat(larva, _holder)
			holding = false
			_teardown_visual()
			return


func _eat(larva: Node, spider: Node) -> void:
	var hunger := _find_hunger(spider)
	var heal_amount: float = larva.heal_value() if larva.has_method("heal_value") else 40.0
	var overflow := 0.0
	if hunger != null:
		overflow = hunger.satiate(heal_amount)
	EventBus.larva_consumed.emit(spider, overflow)
	if overflow > 0.0:
		EventBus.excess_consumed.emit(spider, overflow)
	if is_instance_valid(larva):
		larva.queue_free()


func _nearest_ready_trap(source: Node2D) -> WebTrap:
	if source == null:
		return null
	var best: WebTrap = null
	var best_dist := reach
	for node in source.get_tree().get_nodes_in_group("traps"):
		var trap := node as WebTrap
		if trap == null or trap.spent or trap.owner_spider != source:
			continue
		var d := source.global_position.distance_to(trap.global_position)
		if d <= best_dist:
			best_dist = d
			best = trap
	return best


func _forward_tile_position(source: Node2D) -> Vector2:
	var facing: Vector2 = source.get("facing") if "facing" in source else Vector2.RIGHT
	return source.global_position + facing * _tile_size(source)


func _tile_size(source: Node2D) -> float:
	var mover := source.get_node_or_null("GridMover") as GridMover
	return float(mover.tile_size) if mover != null else 48.0


func _find_hunger(spider: Node) -> HungerComponent:
	for child in spider.get_children():
		if child is HungerComponent:
			return child
	return null


func _spawn_visual() -> void:
	_visual = HeldTrapVisual.new()
	_spawn_parent(_holder).add_child(_visual)
	_visual.global_position = _forward_tile_position(_holder)
	_visual.queue_redraw()


func _teardown_visual() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	_visual = null


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene

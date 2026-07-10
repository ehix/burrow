class_name NetShot
extends Area2D
## Net-Caster's fast capture projectile (rework). Travels far faster than a
## normal WebShot; on a landed hit it dispatches by what it struck: a larva
## hands off to the firing NetShotSkill's resolve_larva_hit() (captured
## alive, not killed); a spider hurtbox hands off to resolve_hit() (hard
## immobilize + status-copy, unchanged from the pre-rework net); a placed
## trap/blockade takes a destructive hit like a normal WebShot; a wall just
## stops it. Collision mask = world(1) | larva(8) | hurtbox(16) | trap(32) =
## 57 — matches WebShot's, unlike the old hurtbox-only net (mask 17).
## Placeholder visual: a small drawn diamond (no art asset yet), matching
## CombatFx.SlashVisual's own placeholder-graphic convention.

@export var speed: float = 900.0
@export var max_lifetime: float = 1.2

var _velocity := Vector2.ZERO
var _source: Node = null
var _skill: NetShotSkill = null
var _spent := false
var _life := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


## Called by NetShotSkill right after spawn.
func launch(direction: Vector2, source: Node, skill: NetShotSkill) -> void:
	var dir := direction.normalized()
	_velocity = dir * speed
	_source = source
	_skill = skill
	rotation = dir.angle()


func _physics_process(delta: float) -> void:
	global_position += _velocity * delta
	_life += delta
	if _life >= max_lifetime:
		_despawn()


func _draw() -> void:
	var half := 6.0
	var pts := PackedVector2Array([Vector2(half, 0), Vector2(0, half), Vector2(-half, 0), Vector2(0, -half)])
	draw_colored_polygon(pts, Color(0.75, 0.75, 0.7, 0.85))
	draw_line(pts[0], pts[2], Color(0.4, 0.4, 0.35), 1.0)
	draw_line(pts[1], pts[3], Color(0.4, 0.4, 0.35), 1.0)


func _on_body_entered(body: Node2D) -> void:
	if _spent:
		return
	if body is WebTrap:
		(body as WebTrap).take_web_hit()
	elif body is Blockade:
		(body as Blockade).take_hit(_velocity.normalized())
	elif body.is_in_group("larvae"):
		if _skill != null:
			_skill.resolve_larva_hit(_source, body, global_position)
	# else: a wall — nothing to do but stop.
	_despawn()


func _on_area_entered(area: Area2D) -> void:
	if _spent or not (area is Hurtbox):
		return
	var hurtbox := area as Hurtbox
	var victim: Node = hurtbox.owner if hurtbox.owner != null else hurtbox.get_parent()
	if victim == _source:
		return
	if _skill != null and victim != null:
		_skill.resolve_hit(_source, victim)
	_despawn()


func _despawn() -> void:
	if _spent:
		return
	_spent = true
	queue_free()

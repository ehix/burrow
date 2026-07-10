class_name NetShot
extends Area2D
## Net-Caster's non-damaging net projectile (design §3). Travels like a web
## shot but deals no damage; on a landed hit it hands off to the firing
## NetProjectileSkill's resolve_hit() for the actual immobilize + status-
## effect copy. Collision mask = world(1) | hurtbox(16) = 17 — nets ignore
## larvae/traps, unlike a real web shot. Placeholder visual: a small drawn
## diamond (no art asset yet) via _draw(), matching CombatFx.SlashVisual's
## own placeholder-graphic convention.

@export var speed: float = 300.0
@export var max_lifetime: float = 1.5

var _velocity := Vector2.ZERO
var _source: Node = null
var _skill: NetProjectileSkill = null
var _spent := false
var _life := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


## Called by NetProjectileSkill right after spawn.
func launch(direction: Vector2, source: Node, skill: NetProjectileSkill) -> void:
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


func _on_body_entered(_body: Node2D) -> void:
	_despawn() # a wall — nothing to do but stop


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

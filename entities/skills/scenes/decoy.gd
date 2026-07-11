class_name Decoy
extends StaticBody2D
## Decoy Spider's effigy (design §3): a static illusion dropped to divert
## enemy aggro. Reuses the same HealthComponent/Hurtbox pair every real
## spider uses, so the existing melee/web-shot attack code already resolves
## against it with zero special-casing (Player._melee's "spiders" group loop
## and WebShot's generic Hurtbox check both already work against it as-is)
## — it "dies" and frees itself exactly like a real spider would. Placeholder
## visual: a dim silhouette, no art asset yet.
##
## Retargeting is already wired: Enemy._acquire_target() prefers a nearer
## visible decoy over the real player (see tests/test_enemy_decoy_diversion.gd).
## No physical collision (skill fixes bundle) — a decoy is dropped on the
## caster's own tile, and being a solid obstacle there trapped the caster
## against its own decoy the instant it was placed.

@onready var _health: HealthComponent = $HealthComponent

var _lifetime_left: float = 0.0


## Called by DecoySkill right after placement.
func setup(lifetime: float) -> void:
	_lifetime_left = lifetime


func _ready() -> void:
	add_to_group("spiders")
	add_to_group("decoys")
	_health.died.connect(queue_free)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 10.0, Color(0.6, 0.6, 0.65, 0.5))


func _physics_process(delta: float) -> void:
	_lifetime_left -= delta
	if _lifetime_left <= 0.0:
		queue_free()


## A landed hit shoves/stuns a real spider (Player/Enemy) — a no-op here
## since a decoy doesn't actually move, but Player._melee calls this
## unconditionally via has_method(), so it must exist.
func apply_web_hit(_push_dir: Vector2i, _factor: float, _slow_duration: float, _stun_duration: float) -> void:
	pass

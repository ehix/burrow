extends GutTest
## NetProjectileSkill's contract (design §3): resolve_hit() immobilizes the
## victim without damage/slow, and copies the shooter's active status
## effects onto it — the "inherits status effects" clause.

class RecordingVictim:
	extends Node2D
	var calls: Array = []
	func apply_web_hit(push_dir: Vector2i, factor: float, slow_duration: float, stun_duration: float) -> void:
		calls.append([push_dir, factor, slow_duration, stun_duration])


func _make_spider_with_status() -> Node2D:
	var spider := Node2D.new()
	autofree(spider)
	var status := StatusEffectComponent.new()
	spider.add_child(status)
	return spider


func test_resolve_hit_fully_immobilizes_with_no_slow() -> void:
	var skill := NetProjectileSkill.new()
	autofree(skill)
	skill.immobilize_duration = 2.5
	var shooter := _make_spider_with_status()
	var victim := RecordingVictim.new()
	autofree(victim)

	skill.resolve_hit(shooter, victim)

	assert_eq(victim.calls.size(), 1)
	var call: Array = victim.calls[0]
	assert_eq(call[0], Vector2i.ZERO, "no shove")
	assert_eq(call[1], 1.0, "no slow — factor 1.0")
	assert_eq(call[2], 0.0, "no slow duration")
	assert_eq(call[3], 2.5, "full stun duration")


func test_resolve_hit_copies_the_shooters_active_status_effects() -> void:
	var skill := NetProjectileSkill.new()
	autofree(skill)
	var shooter := _make_spider_with_status()
	var shooter_status := shooter.get_child(0) as StatusEffectComponent
	shooter_status.apply(&"venomous", 3.0, 10.0)

	var victim := RecordingVictim.new()
	autofree(victim)
	var victim_status := StatusEffectComponent.new()
	victim.add_child(victim_status)

	skill.resolve_hit(shooter, victim)

	assert_true(victim_status.has(&"venomous"))
	assert_eq(victim_status.magnitude(&"venomous"), 3.0)


func test_resolve_hit_without_a_victim_status_component_is_a_noop() -> void:
	var skill := NetProjectileSkill.new()
	autofree(skill)
	var shooter := _make_spider_with_status()
	var victim := RecordingVictim.new()
	autofree(victim)

	skill.resolve_hit(shooter, victim) # victim has no StatusEffectComponent — must not error

	assert_eq(victim.calls.size(), 1, "the immobilize itself still lands")

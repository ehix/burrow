extends GutTest
## NetShotSkill's contract (Net-caster rework): only fires while holding a
## trap (spends it on activation, via NetHoldSkill.spend()); on a spider hit,
## resolve_hit() keeps the pre-rework hard immobilize + status-copy
## unchanged; on a larva hit, resolve_larva_hit() captures it alive (spawns
## a live, consumable WebTrap) instead of killing it outright.

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
	var skill := NetShotSkill.new()
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
	var skill := NetShotSkill.new()
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
	var skill := NetShotSkill.new()
	autofree(skill)
	var shooter := _make_spider_with_status()
	var victim := RecordingVictim.new()
	autofree(victim)

	skill.resolve_hit(shooter, victim)

	assert_eq(victim.calls.size(), 1, "the immobilize itself still lands")


func test_activate_is_a_noop_when_not_holding() -> void:
	var skill := NetShotSkill.new()
	add_child_autofree(skill)
	var hold := NetHoldSkill.new()
	add_child_autofree(hold)
	skill.net_hold = hold
	var shooter := Node2D.new()
	autofree(shooter)

	var fired := skill.activate(shooter)

	assert_false(fired, "nothing to fire — no trap held")


func test_activate_spends_the_held_trap() -> void:
	var skill := NetShotSkill.new()
	add_child_autofree(skill)
	var hold := NetHoldSkill.new()
	add_child_autofree(hold)
	skill.net_hold = hold
	hold.holding = true # simulate an already-held trap without a full pickup
	var shooter := Node2D.new()
	add_child_autofree(shooter)

	skill.activate(shooter)

	assert_false(hold.holding, "firing spends the held trap")


func test_resolve_larva_hit_captures_instead_of_killing() -> void:
	var skill := NetShotSkill.new()
	add_child_autofree(skill)
	var shooter := Node2D.new()
	add_child_autofree(shooter)
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	add_child_autofree(larva)

	skill.resolve_larva_hit(shooter, larva, Vector2(100, 100))

	assert_false(larva.is_queued_for_deletion(), "captured, not killed")
	assert_true(WebTrap.tile_has_caught_web(get_tree(), Vector2i(2, 2), 48),
		"a live trap now holds the larva at the impact tile")

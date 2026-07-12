extends GutTest
## SkillComponent (UI/HUD overhaul): remaining_cooldown() exposes the
## private cooldown timer read-only, for a HUD to poll without needing
## write access to _cooldown_left. display_name/description are new
## per-instance metadata, authored the same way cooldown/hunger_cost
## already are.


func test_remaining_cooldown_is_zero_before_first_activation() -> void:
	var skill := SkillComponent.new()
	add_child_autofree(skill)
	assert_eq(skill.remaining_cooldown(), 0.0)


func test_remaining_cooldown_reflects_cooldown_after_activate() -> void:
	var skill := SkillComponent.new()
	skill.cooldown = 5.0
	add_child_autofree(skill)
	var caster := Node2D.new()
	add_child_autofree(caster)

	skill.activate(caster)

	assert_eq(skill.remaining_cooldown(), 5.0)


func test_remaining_cooldown_ticks_down_and_reaches_zero() -> void:
	var skill := SkillComponent.new()
	skill.cooldown = 1.0
	add_child_autofree(skill)
	var caster := Node2D.new()
	add_child_autofree(caster)
	skill.activate(caster)

	skill._process(0.6)
	assert_almost_eq(skill.remaining_cooldown(), 0.4, 0.001)
	skill._process(0.5)
	assert_eq(skill.remaining_cooldown(), 0.0)


func test_display_name_and_description_default_to_empty_string() -> void:
	var skill := SkillComponent.new()
	add_child_autofree(skill)
	assert_eq(skill.display_name, "")
	assert_eq(skill.description, "")


class DeferringSkill:
	extends SkillComponent

	func _defer_cooldown() -> bool:
		return true


func test_non_deferring_skill_arms_cooldown_immediately_on_activate() -> void:
	var skill := SkillComponent.new()
	skill.cooldown = 5.0
	add_child_autofree(skill)
	var caster := Node2D.new()
	add_child_autofree(caster)

	skill.activate(caster)

	assert_eq(skill.remaining_cooldown(), 5.0)
	assert_false(skill.can_activate())


func test_deferring_skill_stays_non_reactivatable_even_after_cooldown_duration_elapses() -> void:
	var skill := DeferringSkill.new()
	skill.cooldown = 5.0
	add_child_autofree(skill)
	var caster := Node2D.new()
	add_child_autofree(caster)
	skill.activate(caster)

	skill._process(10.0) # well past `cooldown`, but _start_deferred_cooldown() was never called

	assert_false(skill.can_activate(), "stays busy until the subclass explicitly starts the real cooldown")
	assert_eq(skill.remaining_cooldown(), 5.0, "shows the frozen cooldown value, not a ticked-down one")


func test_deferring_skill_starts_the_real_cooldown_once_told_to() -> void:
	var skill := DeferringSkill.new()
	skill.cooldown = 5.0
	add_child_autofree(skill)
	var caster := Node2D.new()
	add_child_autofree(caster)
	skill.activate(caster)

	skill._start_deferred_cooldown()

	assert_eq(skill.remaining_cooldown(), 5.0)
	skill._process(2.0)
	assert_almost_eq(skill.remaining_cooldown(), 3.0, 0.001, "counts down for real now")


func test_deferring_skill_can_activate_again_once_cooldown_elapses() -> void:
	var skill := DeferringSkill.new()
	skill.cooldown = 1.0
	add_child_autofree(skill)
	var caster := Node2D.new()
	add_child_autofree(caster)
	skill.activate(caster)
	skill._start_deferred_cooldown()

	skill._process(1.0)

	assert_true(skill.can_activate())

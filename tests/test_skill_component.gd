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

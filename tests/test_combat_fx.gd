extends GutTest
## CombatFx.flash() must restore the sprite's own prior tint, not a
## hardcoded white — otherwise a class-colored (or ceiling-tinted) sprite
## would incorrectly snap back to plain white after every hit.

func test_flash_sets_the_flash_color_immediately() -> void:
	var sprite := Sprite2D.new()
	add_child_autofree(sprite)
	sprite.modulate = Color(0.4, 0.75, 0.45) # some non-white class tint
	CombatFx.flash(sprite)
	assert_eq(sprite.modulate, CombatFx.FLASH_COLOR)


func test_flash_restores_the_sprites_actual_prior_tint_not_white() -> void:
	var sprite := Sprite2D.new()
	add_child_autofree(sprite)
	var class_tint := Color(0.4, 0.75, 0.45)
	sprite.modulate = class_tint
	CombatFx.flash(sprite)
	await get_tree().create_timer(CombatFx.FLASH_TIME + 0.05).timeout
	assert_eq(sprite.modulate, class_tint, "restores the actual prior tint, not hardcoded white")


func test_flash_is_a_noop_outside_the_tree() -> void:
	var sprite := Sprite2D.new()
	autofree(sprite) # deliberately not added to the tree
	sprite.modulate = Color(0.4, 0.75, 0.45)
	CombatFx.flash(sprite) # must not error
	assert_eq(sprite.modulate, Color(0.4, 0.75, 0.45), "no-op leaves modulate untouched")


func test_spawn_collapse_dust_adds_a_node_under_holder() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)

	CombatFx.spawn_collapse_dust(holder, Vector2(100, 100))

	assert_eq(holder.get_child_count(), 1, "spawns exactly one dust node")


func test_spawn_collapse_dust_frees_itself_after_its_tween() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)

	CombatFx.spawn_collapse_dust(holder, Vector2(100, 100))
	var dust: Node = holder.get_child(0)

	await get_tree().create_timer(0.4).timeout

	assert_false(is_instance_valid(dust), "the dust cloud frees itself once its tween finishes")

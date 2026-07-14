extends GutTest
## OutlineFx (skill fixes bundle): shared static helper for toggling the
## outline shader on a sprite, used by Sense and Camouflage alike. Lazily
## creates and caches one ShaderMaterial per sprite rather than stacking a
## new one on every call.


func _make_sprite() -> Sprite2D:
	var sprite := Sprite2D.new()
	add_child_autofree(sprite)
	return sprite


func test_set_outline_true_attaches_the_shader_material() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_outline(sprite, true, Color.RED)

	var mat := sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_eq(mat.shader, OutlineFx.OutlineShader)
	assert_true(mat.get_shader_parameter("outline_enabled"))
	assert_eq(mat.get_shader_parameter("outline_color"), Color.RED)


## Once the only caller that wanted the outline releases it, and body_alpha
## is still its neutral 1.0 (never touched by this test), the material is
## detached entirely rather than left attached-but-neutral (playtest fix:
## a lingering "neutral" ShaderMaterial from a ceiling-plane dim never came
## back off even once fully neutral) -- see OutlineFx._release_if_neutral()'s
## own doc comment.
func test_set_outline_false_after_the_only_caller_releases_the_material() -> void:
	var sprite := _make_sprite()
	OutlineFx.set_outline(sprite, true, Color.RED)

	OutlineFx.set_outline(sprite, false)

	assert_null(sprite.material, "no caller wants the effect anymore -- the material is fully released, not left neutral")


func test_repeated_calls_reuse_the_same_material_instead_of_stacking() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_outline(sprite, true, Color.RED)
	var first_mat := sprite.material
	OutlineFx.set_outline(sprite, true, Color.BLUE)
	var second_mat := sprite.material

	assert_eq(first_mat, second_mat, "the same ShaderMaterial instance is reused, not replaced")


func test_set_outline_on_null_sprite_is_a_noop() -> void:
	OutlineFx.set_outline(null, true, Color.RED) # must not error
	assert_true(true, "reached this point without erroring")


## Reference-counting (final-review fix): two independent callers both
## wanting the outline on (e.g. Sense's blanket effect and Camouflage on the
## same enemy sprite) must not let one caller's "off" turn it off for both.
func test_two_on_calls_then_one_off_leaves_outline_still_enabled() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_outline(sprite, true, Color.RED) # caller A on
	OutlineFx.set_outline(sprite, true, Color.BLUE) # caller B on
	OutlineFx.set_outline(sprite, false) # caller A off

	var mat := sprite.material as ShaderMaterial
	assert_true(mat.get_shader_parameter("outline_enabled"),
		"caller B still wants the outline on")


## Once every caller that asked for the outline has released it, it actually
## turns off -- and, with nothing left needing the shader, the material is
## released entirely too.
func test_two_on_calls_then_two_off_calls_releases_the_material() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_outline(sprite, true, Color.RED) # caller A on
	OutlineFx.set_outline(sprite, true, Color.BLUE) # caller B on
	OutlineFx.set_outline(sprite, false) # caller A off
	OutlineFx.set_outline(sprite, false) # caller B off

	assert_null(sprite.material, "both callers released it -- nothing left needing the shader")


## An "off" call with no matching prior "on" call must floor at zero rather
## than go negative — still ends up with no material at all, never errors.
func test_off_call_with_no_prior_on_call_does_not_go_negative() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_outline(sprite, false) # no matching "on" — must not error

	assert_null(sprite.material)


func test_set_body_alpha_sets_the_shader_uniform() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_body_alpha(sprite, 0.15)

	var mat := sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), 0.15, 0.001)


func test_set_body_alpha_on_null_sprite_is_a_noop() -> void:
	OutlineFx.set_body_alpha(null, 0.5) # must not error
	assert_true(true, "reached this point without erroring")


## The exact bug found via playtest: Level._refresh_plane_focus() dims an
## off-plane spider via set_body_alpha() on a ceiling transition, then
## restores it to 1.0 on the way back -- the shader must actually come off,
## not just numerically neutralize while staying attached.
func test_set_body_alpha_back_to_neutral_releases_the_material() -> void:
	var sprite := _make_sprite()
	OutlineFx.set_body_alpha(sprite, 0.4) # e.g. dimmed while off the player's plane
	assert_not_null(sprite.material)

	OutlineFx.set_body_alpha(sprite, 1.0) # e.g. back on the same plane

	assert_null(sprite.material,
		"back to neutral -- the shader comes off entirely, not just numerically neutral")


func test_set_body_alpha_at_1_on_an_untouched_sprite_never_creates_a_material() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_body_alpha(sprite, 1.0)

	assert_null(sprite.material, "the common case (never left its own plane) never even touches the shader")


func test_set_body_alpha_reuses_the_same_material_set_outline_uses() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_outline(sprite, true, Color.RED)
	var mat_after_outline := sprite.material
	OutlineFx.set_body_alpha(sprite, 0.5)
	var mat_after_alpha := sprite.material

	assert_eq(mat_after_outline, mat_after_alpha, "one shared material, not a second one stacked on")

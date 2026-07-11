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


func test_set_outline_false_disables_without_erroring() -> void:
	var sprite := _make_sprite()
	OutlineFx.set_outline(sprite, true, Color.RED)

	OutlineFx.set_outline(sprite, false)

	var mat := sprite.material as ShaderMaterial
	assert_false(mat.get_shader_parameter("outline_enabled"))


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

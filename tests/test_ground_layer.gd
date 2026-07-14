extends GutTest
## GroundLayer (tunnel visual rework Phase 2): a CanvasGroup carrying the
## desaturate/darken shader for the "hazy background" read while the
## player is on the ceiling. set_dimmed() lazily creates the material on
## _ready() and just flips one uniform -- no ref-counting needed (unlike
## OutlineFx's outline toggle), since only Level's own plane-focus refresh
## ever calls this for one node.

func _make_ground_layer() -> GroundLayer:
	var layer := GroundLayer.new()
	add_child_autofree(layer)
	return layer


func test_ready_creates_the_shader_material() -> void:
	var layer := _make_ground_layer()

	var mat := layer.material as ShaderMaterial
	assert_not_null(mat)
	assert_eq(mat.shader, GroundLayer.GroundDimShader)


func test_set_dimmed_true_sets_the_shader_parameter() -> void:
	var layer := _make_ground_layer()

	layer.set_dimmed(true)

	var mat := layer.material as ShaderMaterial
	assert_true(mat.get_shader_parameter("dim_enabled"))


func test_set_dimmed_false_clears_the_shader_parameter() -> void:
	var layer := _make_ground_layer()
	layer.set_dimmed(true)

	layer.set_dimmed(false)

	var mat := layer.material as ShaderMaterial
	assert_false(mat.get_shader_parameter("dim_enabled"))

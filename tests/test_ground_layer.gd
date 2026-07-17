extends GutTest
## GroundLayer (tunnel visual rework Phase 2): a plain Node2D carrying the
## shared desaturate/darken ShaderMaterial for the "hazy background" read
## while the player is on the ceiling. dim_material() lazily creates the
## material on _ready() (assigning it to FloorRenderer directly) and
## exposes it so Level's spawn methods can assign the same instance to
## every larva/item/hazard marker they add -- not a CanvasGroup, since a
## CanvasGroup with a ShaderMaterial attached never renders any child added
## after that assignment (confirmed via an isolated repro outside this
## project). set_dimmed() just flips one uniform -- no ref-counting needed
## (unlike OutlineFx's outline toggle), since only Level's own plane-focus
## refresh ever calls this for one node.

func _make_ground_layer() -> GroundLayer:
	var layer := GroundLayer.new()
	var floor_renderer := Node2D.new()
	floor_renderer.name = "FloorRenderer"
	layer.add_child(floor_renderer)
	add_child_autofree(layer)
	return layer


func test_ready_creates_the_shader_material() -> void:
	var layer := _make_ground_layer()

	var mat := layer.dim_material()
	assert_not_null(mat)
	assert_eq(mat.shader, GroundLayer.GroundDimShader)


func test_ready_assigns_the_material_to_floor_renderer() -> void:
	var layer := _make_ground_layer()

	assert_eq(layer.get_node("FloorRenderer").material, layer.dim_material())


func test_set_dimmed_true_sets_the_shader_parameter() -> void:
	var layer := _make_ground_layer()

	layer.set_dimmed(true)

	assert_true(layer.dim_material().get_shader_parameter("dim_enabled"))


func test_set_dimmed_false_clears_the_shader_parameter() -> void:
	var layer := _make_ground_layer()
	layer.set_dimmed(true)

	layer.set_dimmed(false)

	assert_false(layer.dim_material().get_shader_parameter("dim_enabled"))

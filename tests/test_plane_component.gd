extends GutTest
## PlaneComponent's shared static helpers (ceiling/plane mechanics rework):
## effective_plane()/same_plane() default anything without a PlaneComponent
## to GROUND, and apply_hit_fall() is the knockdown-plus-fall-damage penalty
## for getting hit while on the ceiling.

func _make_owner_with_plane(plane: Level.Layer = Level.Layer.GROUND) -> Node2D:
	var owner := Node2D.new()
	add_child_autofree(owner)
	var plane_comp := PlaneComponent.new()
	# A runtime-created node isn't auto-named after its class_name (that only
	# happens for nodes placed in a .tscn) — effective_plane() looks it up as
	# "PlaneComponent" by name, exactly like player.tscn/enemy.tscn wire it,
	# so the test double must match that name too.
	plane_comp.name = "PlaneComponent"
	owner.add_child(plane_comp)
	plane_comp.current_plane = plane
	return owner


func test_effective_plane_defaults_to_ground_without_a_plane_component() -> void:
	var owner := Node2D.new()
	add_child_autofree(owner)

	assert_eq(PlaneComponent.effective_plane(owner), Level.Layer.GROUND)


func test_effective_plane_defaults_to_ground_for_null() -> void:
	assert_eq(PlaneComponent.effective_plane(null), Level.Layer.GROUND)


func test_effective_plane_reads_the_plane_component_when_present() -> void:
	var owner := _make_owner_with_plane(Level.Layer.CEILING)

	assert_eq(PlaneComponent.effective_plane(owner), Level.Layer.CEILING)


func test_same_plane_true_when_both_ground_by_default() -> void:
	var a := Node2D.new()
	var b := Node2D.new()
	add_child_autofree(a)
	add_child_autofree(b)

	assert_true(PlaneComponent.same_plane(a, b))


func test_same_plane_false_when_planes_differ() -> void:
	var a := _make_owner_with_plane(Level.Layer.GROUND)
	var b := _make_owner_with_plane(Level.Layer.CEILING)

	assert_false(PlaneComponent.same_plane(a, b))


func test_apply_hit_fall_transitions_to_ground_and_deals_fall_damage_from_ceiling() -> void:
	var plane_comp := PlaneComponent.new()
	add_child_autofree(plane_comp)
	plane_comp.current_plane = Level.Layer.CEILING
	plane_comp.fall_damage = 8.0
	var health := HealthComponent.new()
	health.max_health = 100.0
	add_child_autofree(health)
	health.current_health = 50.0

	plane_comp.apply_hit_fall(health)

	assert_eq(plane_comp.current_plane, Level.Layer.GROUND, "knocked down to the ground")
	assert_almost_eq(health.current_health, 42.0, 0.001, "eats the bonus fall-damage tick")


func test_apply_hit_fall_is_a_noop_while_already_on_the_ground() -> void:
	var plane_comp := PlaneComponent.new()
	add_child_autofree(plane_comp)
	plane_comp.current_plane = Level.Layer.GROUND
	var health := HealthComponent.new()
	health.max_health = 100.0
	add_child_autofree(health)
	health.current_health = 50.0

	plane_comp.apply_hit_fall(health)

	assert_eq(plane_comp.current_plane, Level.Layer.GROUND)
	assert_almost_eq(health.current_health, 50.0, 0.001, "no extra damage from the ground")

extends GutTest
## LarvaGrowth (design §2): size_scale and heal_value both grow with age, and
## size_scale caps out rather than growing unbounded.


func _make() -> LarvaGrowth:
	var growth := LarvaGrowth.new()
	autofree(growth)
	return growth


func test_starts_at_base_size_and_heal_value() -> void:
	var growth := _make()
	assert_eq(growth.size_scale, 1.0)
	assert_eq(growth.heal_value(), LarvaGrowth.BASE_HEAL_VALUE)


func test_size_and_heal_value_grow_with_age() -> void:
	var growth := _make()
	growth.tick(10.0)
	assert_gt(growth.size_scale, 1.0)
	assert_gt(growth.heal_value(), LarvaGrowth.BASE_HEAL_VALUE)


func test_size_scale_caps_at_max() -> void:
	var growth := _make()
	growth.tick(100000.0)
	assert_eq(growth.size_scale, LarvaGrowth.MAX_SIZE_SCALE)


func test_heal_value_scales_proportionally_with_size() -> void:
	var growth := _make()
	growth.size_scale = 2.0 # a larva at double size...
	var expected := LarvaGrowth.BASE_HEAL_VALUE + LarvaGrowth.HEAL_PER_SIZE * 1.0
	assert_eq(growth.heal_value(), expected)

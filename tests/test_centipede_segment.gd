extends GutTest
## CentipedeSegment (Centipede entity, sub-project H): a purely physical/
## visual leaf -- take_hit() forwards to whatever parent it's under, since
## the real Centipede owns the actual shared hit counter (tested here via a
## lightweight double, not the real Centipede, which doesn't exist until a
## later task in this plan).

class FakeCentipedeBody:
	extends Node2D
	var hits := 0
	func take_hit() -> void:
		hits += 1

const SegmentScene := preload("res://entities/centipede/centipede_segment.tscn")


func _make_segment(parent: Node2D) -> CentipedeSegment:
	var segment: CentipedeSegment = SegmentScene.instantiate()
	parent.add_child(segment)
	return segment


func test_joins_the_centipede_segments_group() -> void:
	var body := FakeCentipedeBody.new()
	add_child_autofree(body)
	var segment := _make_segment(body)
	assert_true(segment.is_in_group("centipede_segments"))


func test_take_hit_forwards_to_the_parent() -> void:
	var body := FakeCentipedeBody.new()
	add_child_autofree(body)
	var segment := _make_segment(body)
	segment.take_hit()
	assert_eq(body.hits, 1)


func test_take_hit_forwards_every_time_not_just_once() -> void:
	var body := FakeCentipedeBody.new()
	add_child_autofree(body)
	var segment := _make_segment(body)
	segment.take_hit()
	segment.take_hit()
	segment.take_hit()
	assert_eq(body.hits, 3, "a segment holds no state of its own -- every hit forwards")


func test_take_hit_nudges_itself_in_the_given_direction() -> void:
	var body := FakeCentipedeBody.new()
	add_child_autofree(body)
	var segment := _make_segment(body)
	var rest := segment.position

	segment.take_hit(Vector2.RIGHT)

	assert_ne(segment.position, rest,
		"a hit visibly nudges the segment (CombatFx.shunt), mirroring Blockade.take_hit()'s own bump")
	assert_eq(body.hits, 1, "still forwards the hit to the parent's shared counter")


func test_radius_for_index_head_is_index_zero() -> void:
	assert_eq(CentipedeSegment.radius_for_index(0, 5), CentipedeSegment.HEAD_RADIUS)


func test_radius_for_index_tail_is_the_last_index() -> void:
	assert_eq(CentipedeSegment.radius_for_index(4, 5), CentipedeSegment.TAIL_RADIUS)


func test_radius_for_index_body_is_any_middle_index() -> void:
	assert_eq(CentipedeSegment.radius_for_index(1, 5), CentipedeSegment.BODY_RADIUS)
	assert_eq(CentipedeSegment.radius_for_index(2, 5), CentipedeSegment.BODY_RADIUS)
	assert_eq(CentipedeSegment.radius_for_index(3, 5), CentipedeSegment.BODY_RADIUS)


func test_radius_for_index_single_segment_body_counts_as_head() -> void:
	assert_eq(CentipedeSegment.radius_for_index(0, 1), CentipedeSegment.HEAD_RADIUS)


func test_random_body_color_stays_within_declared_hsv_bounds() -> void:
	for i in 50:
		var color := CentipedeSegment.random_body_color()
		assert_true(color.h >= CentipedeSegment.HUE_MIN - 0.001 and color.h <= CentipedeSegment.HUE_MAX + 0.001)
		assert_true(color.s >= CentipedeSegment.SATURATION_MIN - 0.01 and color.s <= CentipedeSegment.SATURATION_MAX + 0.01)
		assert_true(color.v >= CentipedeSegment.VALUE_MIN - 0.01 and color.v <= CentipedeSegment.VALUE_MAX + 0.01)


func test_set_visual_assigns_radius_and_tint() -> void:
	var body := FakeCentipedeBody.new()
	add_child_autofree(body)
	var segment := _make_segment(body)

	segment.set_visual(30.0, Color(0.5, 0.3, 0.2))

	assert_eq(segment._radius, 30.0)
	assert_eq(segment._tint, Color(0.5, 0.3, 0.2))

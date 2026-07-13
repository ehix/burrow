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

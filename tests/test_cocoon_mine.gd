extends GutTest
## CocoonMine (design §3): a hidden proximity trap that bursts into
## TinySpiderling attackers around itself once a spider/larva crosses it.

const MineScene := preload("res://entities/skills/scenes/cocoon_mine.tscn")


func _make_mine() -> CocoonMine:
	var mine: CocoonMine = MineScene.instantiate()
	add_child_autofree(mine)
	return mine


func _make_body(group: String) -> Node2D:
	var body := Node2D.new()
	body.add_to_group(group)
	add_child_autofree(body)
	return body


func test_body_entered_by_a_spider_detonates_and_bursts() -> void:
	var mine := _make_mine()
	mine.arm(null, 3)
	var intruder := _make_body("spiders")

	mine._on_body_entered(intruder)

	assert_true(mine.is_queued_for_deletion(), "the mine consumes itself on detonation")
	assert_eq(get_tree().get_nodes_in_group("hatchlings").size(), 3)


func test_body_entered_by_a_larva_also_detonates() -> void:
	var mine := _make_mine()
	mine.arm(null, 2)
	var larva := _make_body("larvae")

	mine._on_body_entered(larva)

	assert_true(mine.is_queued_for_deletion())


func test_ignores_its_own_owner() -> void:
	var mine := _make_mine()
	var owner_spider := _make_body("spiders")
	mine.arm(owner_spider, 3)

	mine._on_body_entered(owner_spider)

	assert_false(mine.is_queued_for_deletion(), "the placer walking over their own mine doesn't trigger it")


func test_ignores_bodies_that_are_neither_a_spider_nor_a_larva() -> void:
	var mine := _make_mine()
	mine.arm(null, 3)
	var wall := StaticBody2D.new()
	add_child_autofree(wall)

	mine._on_body_entered(wall)

	assert_false(mine.is_queued_for_deletion())


func test_unarmed_mine_does_not_detonate() -> void:
	var mine := _make_mine()
	var intruder := _make_body("spiders")

	mine._on_body_entered(intruder) # never armed

	assert_false(mine.is_queued_for_deletion())

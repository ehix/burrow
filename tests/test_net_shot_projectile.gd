extends GutTest
## The Net-caster's fast capture projectile (rework): a much wider collision
## mask than the old net (matches WebShot's world|larva|hurtbox|trap), and
## dispatches by what it strikes — a larva hands off to the firing skill's
## resolve_larva_hit() (capture, not kill); a spider hurtbox hands off to
## resolve_hit() (unchanged hard immobilize); traps and blockades take a
## destructive hit like a normal web shot. Drives the collision callbacks
## directly (no physics frames), mirroring test_web_shot.gd's convention.

const NetShotScene := preload("res://entities/skills/scenes/net_shot.tscn")
const LarvaScene := preload("res://entities/larva/larva.tscn")


class RecordingSkill:
	extends NetShotSkill
	var larva_hits: Array = []
	var spider_hits: Array = []
	func resolve_larva_hit(shooter: Node, larva: Node, at_position: Vector2) -> void:
		larva_hits.append([shooter, larva, at_position])
	func resolve_hit(shooter: Node, victim: Node) -> void:
		spider_hits.append([shooter, victim])


func _make_shot() -> NetShot:
	var shot: NetShot = NetShotScene.instantiate()
	add_child_autofree(shot)
	return shot


func _make_larva() -> Larva:
	var larva: Larva = LarvaScene.instantiate()
	add_child_autofree(larva)
	return larva


func test_default_speed_is_much_faster_than_a_web_shot() -> void:
	assert_gt(_make_shot().speed, 340.0 * 2.0, "far faster than WebShot's 340")


func test_hitting_a_larva_hands_off_to_the_firing_skills_capture() -> void:
	var shot := _make_shot()
	var skill := RecordingSkill.new()
	add_child_autofree(skill)
	var shooter := Node2D.new()
	autofree(shooter)
	shot.launch(Vector2.RIGHT, shooter, skill)
	var larva := _make_larva()

	shot._on_body_entered(larva)

	assert_eq(skill.larva_hits.size(), 1)
	assert_eq(skill.larva_hits[0][1], larva)
	assert_false(larva.is_queued_for_deletion(), "captured, not killed outright")


func test_hitting_a_trap_registers_a_destructive_hit() -> void:
	var shot := _make_shot()
	var trap := WebTrap.new()
	add_child_autofree(trap)
	shot._on_body_entered(trap)
	assert_eq(trap.web_hits, 1)


func test_hitting_a_blockade_registers_a_hit() -> void:
	var blockade := Blockade.new()
	add_child_autofree(blockade)
	blockade.setup(3)
	_make_shot()._on_body_entered(blockade)
	assert_false(blockade.is_queued_for_deletion())
	_make_shot()._on_body_entered(blockade)
	_make_shot()._on_body_entered(blockade)
	assert_true(blockade.is_queued_for_deletion())


func test_hitting_a_spider_hurtbox_hands_off_to_resolve_hit() -> void:
	var shot := _make_shot()
	var skill := RecordingSkill.new()
	add_child_autofree(skill)
	var shooter := Node2D.new()
	autofree(shooter)
	shot.launch(Vector2.RIGHT, shooter, skill)

	var victim := Node2D.new()
	add_child_autofree(victim)
	var hurtbox := Hurtbox.new()
	victim.add_child(hurtbox)

	shot._on_area_entered(hurtbox)

	assert_eq(skill.spider_hits.size(), 1)
	assert_eq(skill.spider_hits[0][1], victim)


func test_ignores_its_own_shooters_hurtbox() -> void:
	var shot := _make_shot()
	var skill := RecordingSkill.new()
	add_child_autofree(skill)
	var shooter := Node2D.new()
	add_child_autofree(shooter)
	var hurtbox := Hurtbox.new()
	shooter.add_child(hurtbox)
	shot.launch(Vector2.RIGHT, shooter, skill)

	shot._on_area_entered(hurtbox)

	assert_eq(skill.spider_hits.size(), 0, "a shot never resolves against its own shooter")

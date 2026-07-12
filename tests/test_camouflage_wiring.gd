extends GutTest
## CamouflageSkill wired through Hurtbox.receive_hit (design §3 guardrail:
## strict state exclusion) — an attack breaks camouflage on both the
## attacker and the victim side, via the single choke point every existing
## attack (melee, web shot) already resolves through.


func _make_camouflaged(duration: float = 5.0) -> Dictionary:
	var entity := Node2D.new()
	autofree(entity)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	entity.add_child(sprite)
	var camo := CamouflageSkill.new()
	camo.duration = duration
	entity.add_child(camo)
	camo.activate(entity)
	return {"entity": entity, "camo": camo}


func _make_hurtbox(owner_node: Node) -> Hurtbox:
	var health := HealthComponent.new()
	autofree(health)
	var hurtbox := Hurtbox.new()
	hurtbox.health = health
	owner_node.add_child(hurtbox)
	return hurtbox


func test_activate_sets_body_alpha_to_target_alpha() -> void:
	var setup := _make_camouflaged()
	var camo: CamouflageSkill = setup["camo"]
	var entity: Node2D = setup["entity"]
	assert_true(camo.active)
	var mat := (entity.get_node("Sprite") as CanvasItem).material as ShaderMaterial
	assert_not_null(mat)
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), camo.target_alpha, 0.001)


func test_activate_applies_the_outline_shader() -> void:
	var setup := _make_camouflaged()
	var entity: Node2D = setup["entity"]

	var mat := (entity.get_node("Sprite") as CanvasItem).material as ShaderMaterial
	assert_not_null(mat)
	assert_true(mat.get_shader_parameter("outline_enabled"))


func test_break_camouflage_disables_the_outline_shader() -> void:
	var setup := _make_camouflaged()
	var camo: CamouflageSkill = setup["camo"]
	var entity: Node2D = setup["entity"]

	camo.break_camouflage()

	var mat := (entity.get_node("Sprite") as CanvasItem).material as ShaderMaterial
	assert_false(mat.get_shader_parameter("outline_enabled"))


func test_break_camouflage_resets_body_alpha_to_one() -> void:
	var setup := _make_camouflaged()
	var camo: CamouflageSkill = setup["camo"]
	var entity: Node2D = setup["entity"]

	camo.break_camouflage()

	var mat := (entity.get_node("Sprite") as CanvasItem).material as ShaderMaterial
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), 1.0, 0.001)


func test_camouflage_breaks_when_the_camouflaged_spider_is_the_victim() -> void:
	var setup := _make_camouflaged()
	var camo: CamouflageSkill = setup["camo"]
	var hurtbox := _make_hurtbox(setup["entity"])

	hurtbox.receive_hit(5.0, null)
	assert_false(camo.active, "the victim's own camouflage breaks on a landed hit")


func test_camouflage_breaks_when_the_camouflaged_spider_is_the_attacker() -> void:
	var attacker_setup := _make_camouflaged()
	var camo: CamouflageSkill = attacker_setup["camo"]

	var victim := Node2D.new()
	autofree(victim)
	var hurtbox := _make_hurtbox(victim)

	hurtbox.receive_hit(5.0, attacker_setup["entity"])
	assert_false(camo.active, "the attacker's own camouflage breaks when it lands a hit")


func test_break_if_present_is_a_noop_without_a_camouflage_skill() -> void:
	var plain := Node2D.new()
	autofree(plain)
	CamouflageSkill.break_if_present(plain) # must not error
	CamouflageSkill.break_if_present(null) # must not error
	assert_true(true, "reached this point without erroring")


func test_camouflage_expires_after_its_duration_elapses() -> void:
	var setup := _make_camouflaged(1.0)
	var camo: CamouflageSkill = setup["camo"]
	camo._process(0.6)
	assert_true(camo.active)
	camo._process(0.5)
	assert_false(camo.active, "camouflage expires once its duration elapses")

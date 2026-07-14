extends GutTest
## Level's plane-focus dimming: whichever of Player/Enemy is off the
## other's plane dims via the shared outline shader's dim_enabled uniform
## (tunnel visual rework Phase 2 — previously a flat body_alpha fade) — the
## GroundLayer dim (see test_ground_layer.gd) tells you which plane you're
## on, this tells you which other spider is or isn't reachable from here.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_refresh_plane_focus_dims_the_enemy_when_only_it_is_on_the_ceiling() -> void:
	var level := _make_level()
	var enemy_plane := level.enemy.get_node("PlaneComponent") as PlaneComponent
	enemy_plane.current_plane = Level.Layer.CEILING

	level._refresh_plane_focus()

	var enemy_sprite := level.enemy.get_node("Sprite") as CanvasItem
	var mat := enemy_sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_true(mat.get_shader_parameter("dim_enabled"), "enemy is off the player's plane, so it reads hazy/desaturated")


func test_refresh_plane_focus_keeps_full_brightness_when_planes_match() -> void:
	var level := _make_level()

	level._refresh_plane_focus() # both default GROUND

	var enemy_sprite := level.enemy.get_node("Sprite") as CanvasItem
	assert_null(enemy_sprite.material,
		"matching planes never need the dim shader at all -- no material is ever created")


func test_plane_changed_event_triggers_a_focus_refresh() -> void:
	var level := _make_level()
	var enemy_plane := level.enemy.get_node("PlaneComponent") as PlaneComponent

	enemy_plane.transition() # fires EventBus.plane_changed(enemy, CEILING)

	var enemy_sprite := level.enemy.get_node("Sprite") as CanvasItem
	var mat := enemy_sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_true(mat.get_shader_parameter("dim_enabled"))


## Camouflage conflict guardrail (design's explicit judgment call): body_alpha
## is not ref-counted, so plane-focus dimming must never clobber an active
## Camouflage's near-invisible body.
func test_refresh_plane_focus_never_touches_a_camouflaged_players_body_alpha() -> void:
	var level := _make_level()
	var camo := level.player.get_node("CamouflageSkill") as CamouflageSkill
	if camo == null:
		pending("current active class has no CamouflageSkill — not exercised this run")
		return
	camo.activate(level.player)
	var player_sprite := level.player.get_node("Sprite") as CanvasItem
	var camo_alpha: float = (player_sprite.material as ShaderMaterial).get_shader_parameter("body_alpha")
	var enemy_plane := level.enemy.get_node("PlaneComponent") as PlaneComponent

	enemy_plane.transition() # triggers a _refresh_plane_focus() via the plane_changed event

	var mat := player_sprite.material as ShaderMaterial
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), camo_alpha, 0.001,
		"plane-focus dimming must not overwrite Camouflage's own body_alpha")


## Enemy-side equivalent of the above: Enemy._make_skills() attaches
## CamouflageSkill at runtime via a bare add_child() (no explicit node name),
## unlike player.tscn's literally-named "CamouflageSkill" child — a
## name-based lookup in _refresh_plane_focus would silently miss this and
## let plane-focus dimming clobber the enemy's camouflaged body_alpha.
func test_refresh_plane_focus_never_touches_a_camouflaged_enemys_body_alpha() -> void:
	var level := _make_level()
	level.enemy._apply_class(SpiderClassData.SpiderClass.DECOY) # only Decoy carries CamouflageSkill
	var camo: CamouflageSkill = null
	for child in level.enemy.get_children():
		if child is CamouflageSkill:
			camo = child
	assert_not_null(camo, "Decoy class should attach a CamouflageSkill")
	camo.activate(level.enemy)
	var enemy_sprite := level.enemy.get_node("Sprite") as CanvasItem
	var camo_alpha: float = (enemy_sprite.material as ShaderMaterial).get_shader_parameter("body_alpha")
	var player_plane := level.player.get_node("PlaneComponent") as PlaneComponent

	player_plane.transition() # triggers a _refresh_plane_focus() via the plane_changed event

	var mat := enemy_sprite.material as ShaderMaterial
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), camo_alpha, 0.001,
		"plane-focus dimming must not overwrite Camouflage's own body_alpha")


func test_refresh_plane_focus_dims_ground_layer_when_player_is_on_ceiling() -> void:
	var level := _make_level()
	var player_plane := level.player.get_node("PlaneComponent") as PlaneComponent
	player_plane.current_plane = Level.Layer.CEILING

	level._refresh_plane_focus()

	var mat := level._ground_layer.material as ShaderMaterial
	assert_true(mat.get_shader_parameter("dim_enabled"), "ground is background while the player is on the ceiling")


func test_refresh_plane_focus_keeps_ground_layer_undimmed_when_player_is_on_ground() -> void:
	var level := _make_level()

	level._refresh_plane_focus() # default GROUND

	var mat := level._ground_layer.material as ShaderMaterial
	assert_false(mat.get_shader_parameter("dim_enabled"), "ground is the plane in focus, not background")

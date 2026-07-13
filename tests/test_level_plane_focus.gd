extends GutTest
## Level's plane-focus dimming (ceiling/plane mechanics rework): whichever of
## Player/Enemy is off the other's plane dims via the shared outline
## shader's body_alpha uniform (already shipped for Camouflage) — the floor
## re-color tells you which plane you're on, this tells you which other
## spider is or isn't reachable from here.

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
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), 0.35, 0.001,
		"enemy is off the player's plane, so it dims")


func test_refresh_plane_focus_keeps_full_brightness_when_planes_match() -> void:
	var level := _make_level()

	level._refresh_plane_focus() # both default GROUND

	var enemy_sprite := level.enemy.get_node("Sprite") as CanvasItem
	var mat := enemy_sprite.material as ShaderMaterial
	if mat != null: # no material yet is equally valid — body_alpha defaults to 1.0
		assert_almost_eq(mat.get_shader_parameter("body_alpha"), 1.0, 0.001)


func test_plane_changed_event_triggers_a_focus_refresh() -> void:
	var level := _make_level()
	var enemy_plane := level.enemy.get_node("PlaneComponent") as PlaneComponent

	enemy_plane.transition() # fires EventBus.plane_changed(enemy, CEILING)

	var enemy_sprite := level.enemy.get_node("Sprite") as CanvasItem
	var mat := enemy_sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), 0.35, 0.001)


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

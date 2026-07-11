extends GutTest
## EggMineSkill (skill fixes bundle): arms the mine on whichever plane the
## caster currently occupies.

## PlayerScene is preloaded before MineScene deliberately: cocoon_mine.gd's
## Level.Layer typing pulls in level.gd, which itself preloads player.tscn
## (an ext_resource of cocoon_mine.tscn) — loading MineScene first re-enters
## cocoon_mine.tscn's own in-flight load and Godot reports it as "referenced
## non-existent resource". Player-first lets that self-reference resolve via
## the normal (harmless) recursive-load path production code already takes.
const PlayerScene := preload("res://entities/player/player.tscn")
const MineScene := preload("res://entities/skills/scenes/cocoon_mine.tscn")


func _make_skill() -> EggMineSkill:
	var skill := EggMineSkill.new()
	skill.mine_scene = MineScene
	skill.burst_count = 2
	add_child_autofree(skill)
	return skill


func test_on_activate_arms_the_mine_on_the_callers_current_plane() -> void:
	var skill := _make_skill()
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	player._plane.transition() # -> CEILING

	skill._on_activate(player)

	var mine: CocoonMine = null
	for node in get_tree().get_nodes_in_group("traps"):
		if node is CocoonMine:
			mine = node
	assert_not_null(mine)
	assert_eq(mine._plane, Level.Layer.CEILING)


func test_on_activate_defaults_to_ground_plane_for_a_caster_without_one() -> void:
	var skill := _make_skill()
	var caster := Node2D.new()
	add_child_autofree(caster)

	skill._on_activate(caster)

	var mine: CocoonMine = null
	for node in get_tree().get_nodes_in_group("traps"):
		if node is CocoonMine:
			mine = node
	assert_not_null(mine)
	assert_eq(mine._plane, Level.Layer.GROUND)

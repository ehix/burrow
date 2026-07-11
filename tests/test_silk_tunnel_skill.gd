extends GutTest
## SilkTunnelSkill (skill fixes bundle): lays web across tile_count tiles
## ahead of the caster — bumped from 4 to 6 per playtest feedback.

const TrapScene := preload("res://entities/web/web_trap.tscn")


func _make_skill() -> SilkTunnelSkill:
	var skill := SilkTunnelSkill.new()
	skill.trap_scene = TrapScene
	add_child_autofree(skill)
	return skill


func test_default_tile_count_is_6() -> void:
	var skill := _make_skill()
	assert_eq(skill.tile_count, 6)

extends GutTest
## SkillBar (UI/HUD overhaul): shows the current class's two skills, their
## keybind/name, and dims + counts down while on cooldown. Re-binds
## automatically when the player's class changes.

const SkillBarScene := preload("res://ui/skill_bar.tscn")
const PlayerScene := preload("res://entities/player/player.tscn")


func _make_bar() -> SkillBar:
	var bar: SkillBar = SkillBarScene.instantiate()
	add_child_autofree(bar)
	return bar


func _make_player() -> Player:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	return player


func test_binds_the_default_classs_two_skills() -> void:
	var bar := _make_bar()
	var player := _make_player() # defaults to Wolf -> hatchlings, egg_mine

	bar.bind_player(player)

	assert_eq(bar._name_label1.text, player._hatchlings.display_name)
	assert_eq(bar._name_label2.text, player._egg_mine.display_name)
	assert_eq(bar._key_label1.text, "Y")
	assert_eq(bar._key_label2.text, "U")


func test_rebinds_when_the_class_changes() -> void:
	var bar := _make_bar()
	var player := _make_player()
	bar.bind_player(player)

	player.apply_class(SpiderClassData.SpiderClass.DECOY)
	EventBus.class_changed.emit(SpiderClassData.SpiderClass.DECOY)

	assert_eq(bar._name_label1.text, player._camouflage.display_name)
	assert_eq(bar._name_label2.text, player._decoy.display_name)


func test_dims_and_counts_down_while_on_cooldown() -> void:
	var bar := _make_bar()
	var player := _make_player()
	bar.bind_player(player)
	player._hatchlings.cooldown = 5.0
	player._hatchlings.activate(player)

	bar._process(0.0)

	assert_eq(bar._panel1.modulate, SkillBar.DIM_COLOR)
	assert_eq(bar._cooldown_label1.text, "5.0")


func test_shows_ready_color_and_no_countdown_once_off_cooldown() -> void:
	var bar := _make_bar()
	var player := _make_player()
	bar.bind_player(player)

	bar._process(0.0)

	assert_eq(bar._panel1.modulate, SkillBar.READY_COLOR)
	assert_eq(bar._cooldown_label1.text, "")

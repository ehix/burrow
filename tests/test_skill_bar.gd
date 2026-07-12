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
	assert_eq(bar._key_label1.text, "V")
	assert_eq(bar._key_label2.text, "B")


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


## Reproduces a real playtest bug: a depth descent frees the old Player (and
## its SkillComponents) one frame before World rebinds the HUD to the new
## one (World._replace_level()'s "await get_tree().process_frame" gap). Any
## _process() tick that lands in that gap must not touch a freed reference —
## drives it through _process() itself, the actual call site in production,
## not _update_cooldown() directly (the freed-reference crash happens at
## the typed-parameter call boundary, before _update_cooldown()'s own body
## ever runs).
func test_process_tolerates_a_freed_skill_reference() -> void:
	var bar := _make_bar()
	var skill := SkillComponent.new()
	bar._skill1 = skill # a valid assignment, same as a normal _rebind()
	skill.free() # the referenced object is freed later — this is the real gap
	bar._panel1.modulate = Color.MAGENTA # sentinel, distinct from DIM_COLOR/READY_COLOR

	bar._process(0.0)

	assert_eq(bar._panel1.modulate, Color.MAGENTA, "a freed skill reference must not be touched further")

extends GutTest
## GameState.selected_class (design §3, dev tool Q): a persistent dev
## preference like darkness_enabled/noclip — survives a run reset.


func before_each() -> void:
	GameState.selected_class = SpiderClassData.SpiderClass.WOLF # defensive, in case another test left it dirty


func after_each() -> void:
	GameState.selected_class = SpiderClassData.SpiderClass.WOLF # restore the default, don't leak


func test_defaults_to_wolf() -> void:
	assert_eq(GameState.selected_class, SpiderClassData.SpiderClass.WOLF)


func test_survives_a_new_run_permadeath_reset() -> void:
	GameState.selected_class = SpiderClassData.SpiderClass.DECOY
	GameState.start_new_run()
	assert_eq(GameState.selected_class, SpiderClassData.SpiderClass.DECOY,
		"a dev preference, like darkness_enabled/noclip — not reset by permadeath")

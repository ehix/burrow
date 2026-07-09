extends GutTest
## The distress flash must only fire on actual damage — never on a pure status
## effect like a web's slow (apply_web_hit with no health cost).

const PlayerScene := preload("res://entities/player/player.tscn")


func _make_player() -> Player:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	return player


func test_apply_web_hit_alone_does_not_flash() -> void:
	var player := _make_player()
	player.apply_web_hit(Vector2i.ZERO, 0.5, 1.5, 0.0) # a pure web-crossing slow
	assert_eq(player.sprite.modulate, Color.WHITE, "a status effect alone must not flash")


func test_actual_damage_still_flashes() -> void:
	var player := _make_player()
	player.health.take_damage(10.0)
	assert_eq(player.sprite.modulate, CombatFx.FLASH_COLOR, "real damage still flashes")

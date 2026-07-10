extends GutTest
## WebEmitter.fire() passes its optional speed_mult straight through to the
## spawned shot's launch() — defaulting to 1.0 (unchanged behavior) when the
## caller doesn't supply one.

const WebShotScene := preload("res://entities/web/web_shot.tscn")


func _make_emitter() -> WebEmitter:
	var emitter := WebEmitter.new()
	emitter.web_shot_scene = WebShotScene
	add_child_autofree(emitter)
	return emitter


func _make_source() -> Node2D:
	var source := Node2D.new()
	add_child_autofree(source)
	return source


func test_fire_defaults_speed_mult_to_one() -> void:
	var emitter := _make_emitter()
	var source := _make_source()
	var shot: WebShot = emitter.fire(Vector2.ZERO, Vector2.RIGHT, source)
	assert_almost_eq(shot._velocity.length(), shot.speed, 0.001)


func test_fire_passes_a_custom_speed_mult_through() -> void:
	var emitter := _make_emitter()
	var source := _make_source()
	var shot: WebShot = emitter.fire(Vector2.ZERO, Vector2.RIGHT, source, 1.4)
	assert_almost_eq(shot._velocity.length(), shot.speed * 1.4, 0.001)

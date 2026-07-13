extends GutTest
## Hurtbox forwards receive_hit to its HealthComponent, resolved from
## health_path in _ready() — a hand-written NodePath in a .tscn does not
## auto-resolve into a Node-typed @export, which is exactly the bug that left
## melee/web-shot damage a silent no-op on both spiders (health stayed null).

const PlayerScene := preload("res://entities/player/player.tscn")
const EnemyScene := preload("res://entities/enemy/enemy.tscn")


func _make_hurtbox_with_health(health_value: float) -> Array:
	var owner := Node2D.new()
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 100.0
	health.current_health = health_value
	owner.add_child(health)
	var hurtbox := Hurtbox.new()
	hurtbox.health_path = NodePath("../HealthComponent")
	owner.add_child(hurtbox)
	add_child_autofree(owner)
	return [hurtbox, health]


func test_health_path_resolves_in_ready() -> void:
	var pair := _make_hurtbox_with_health(100.0)
	var hurtbox: Hurtbox = pair[0]
	assert_not_null(hurtbox.health, "health_path must resolve into a live HealthComponent")


func test_receive_hit_damages_the_resolved_health() -> void:
	var pair := _make_hurtbox_with_health(100.0)
	var hurtbox: Hurtbox = pair[0]
	var health: HealthComponent = pair[1]
	hurtbox.receive_hit(20.0)
	assert_almost_eq(health.current_health, 80.0, 0.001)


func test_receive_hit_is_a_noop_without_a_resolved_health() -> void:
	var hurtbox := Hurtbox.new()
	add_child_autofree(hurtbox)
	hurtbox.receive_hit(20.0) # must not error
	assert_null(hurtbox.health)


## Regression: the real bug had the .tscn's health property name mismatched
## against the script's exported field, so this specifically checks the
## shipped scenes, not just the component in isolation.
func test_player_scene_hurtbox_resolves_its_health() -> void:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	var hurtbox := player.get_node("Hurtbox") as Hurtbox
	assert_not_null(hurtbox.health, "player.tscn's Hurtbox must resolve to the real HealthComponent")
	var before := player.health.current_health
	hurtbox.receive_hit(10.0)
	assert_almost_eq(player.health.current_health, before - 10.0, 0.001)


func test_enemy_scene_hurtbox_resolves_its_health() -> void:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	var hurtbox := enemy.get_node("Hurtbox") as Hurtbox
	assert_not_null(hurtbox.health, "enemy.tscn's Hurtbox must resolve to the real HealthComponent")
	var before := enemy.health.current_health
	hurtbox.receive_hit(10.0)
	assert_almost_eq(enemy.health.current_health, before - 10.0, 0.001)


func test_receive_hit_is_a_noop_when_attacker_and_victim_are_on_different_planes() -> void:
	var pair := _make_hurtbox_with_health(100.0)
	var hurtbox: Hurtbox = pair[0]
	var health: HealthComponent = pair[1]
	# PlaneComponent.new() must be explicitly named — a runtime-created node
	# isn't auto-named after its class_name (that only happens for nodes
	# placed in a .tscn), and effective_plane() looks it up as
	# "PlaneComponent" by name, exactly like player.tscn/enemy.tscn wire it.
	var victim_plane := PlaneComponent.new()
	victim_plane.name = "PlaneComponent"
	hurtbox.get_parent().add_child(victim_plane)
	victim_plane.current_plane = Level.Layer.GROUND
	var attacker := Node2D.new()
	add_child_autofree(attacker)
	var attacker_plane := PlaneComponent.new()
	attacker_plane.name = "PlaneComponent"
	attacker.add_child(attacker_plane)
	attacker_plane.current_plane = Level.Layer.CEILING

	hurtbox.receive_hit(10.0, attacker)

	assert_almost_eq(health.current_health, 100.0, 0.001, "a cross-plane hit never lands")


func test_receive_hit_lands_normally_when_both_default_to_ground() -> void:
	var pair := _make_hurtbox_with_health(100.0)
	var hurtbox: Hurtbox = pair[0]
	var health: HealthComponent = pair[1]
	var attacker := Node2D.new()
	add_child_autofree(attacker)

	hurtbox.receive_hit(10.0, attacker)

	assert_almost_eq(health.current_health, 90.0, 0.001, "neither side has a PlaneComponent, so both default to GROUND")


func test_receive_hit_knocks_a_ceiling_victim_down_and_applies_fall_damage() -> void:
	var pair := _make_hurtbox_with_health(100.0)
	var hurtbox: Hurtbox = pair[0]
	var health: HealthComponent = pair[1]
	var victim_plane := PlaneComponent.new()
	victim_plane.name = "PlaneComponent"
	hurtbox.get_parent().add_child(victim_plane)
	victim_plane.current_plane = Level.Layer.CEILING
	victim_plane.fall_damage = 8.0
	var attacker := Node2D.new()
	add_child_autofree(attacker)
	var attacker_plane := PlaneComponent.new()
	attacker_plane.name = "PlaneComponent"
	attacker.add_child(attacker_plane)
	attacker_plane.current_plane = Level.Layer.CEILING # same plane, so the hit lands

	hurtbox.receive_hit(10.0, attacker)

	assert_eq(victim_plane.current_plane, Level.Layer.GROUND, "knocked down by the hit")
	assert_almost_eq(health.current_health, 82.0, 0.001, "10 damage from the hit, 8 more from the fall")

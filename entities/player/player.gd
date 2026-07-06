class_name Player
extends CharacterBody2D
## Player spider: free 8-way movement, fires web shots along its facing, lays
## traps, and carries HP + Hunger (via child components) between levels. Relays
## its component signals to the EventBus so the generic HUD can listen.

@export var move_speed: float = 130.0

@onready var health: HealthComponent = $HealthComponent
@onready var hunger: HungerComponent = $HungerComponent
@onready var web_emitter: WebEmitter = $WebEmitter
@onready var trap_placer: TrapPlacer = $TrapPlacer

var facing := Vector2.RIGHT
var _dead := false


func _ready() -> void:
	add_to_group("spiders")
	add_to_group("player")
	_restore_vitals()
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(func(amount: float) -> void: EventBus.player_damaged.emit(amount))
	health.died.connect(_on_died)
	hunger.hunger_changed.connect(_on_hunger_changed)
	hunger.overflowed.connect(func(amount: float) -> void: EventBus.excess_consumed.emit(self, amount))
	# Prime the HUD with current values.
	EventBus.health_changed.emit(self, health.current_health, health.max_health)
	EventBus.hunger_changed.emit(self, hunger.current_hunger, hunger.max_hunger)


func _physics_process(_delta: float) -> void:
	if _dead:
		return
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input * move_speed
	if input != Vector2.ZERO:
		facing = input.normalized()
	move_and_slide()

	if Input.is_action_pressed("fire"):
		web_emitter.fire(global_position, facing, self)
	if Input.is_action_just_pressed("place_trap"):
		trap_placer.place(global_position, self)


## Snapshot vitals into GameState before the level is freed on descent.
func store_vitals() -> void:
	GameState.store_player_vitals(health.current_health, hunger.current_hunger)


func _restore_vitals() -> void:
	health.max_health = GameState.DEFAULT_MAX_HEALTH
	if GameState.has_carried_vitals():
		health.current_health = clampf(GameState.carried_health, 0.0, health.max_health)
		hunger.current_hunger = clampf(GameState.carried_hunger, 0.0, hunger.max_hunger)
	else:
		health.current_health = health.max_health
		hunger.current_hunger = 0.0


func _on_health_changed(value: float, max_value: float) -> void:
	EventBus.health_changed.emit(self, value, max_value)


func _on_hunger_changed(value: float, max_value: float) -> void:
	EventBus.hunger_changed.emit(self, value, max_value)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	EventBus.player_died.emit()

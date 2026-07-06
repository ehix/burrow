class_name EnemyType
extends Resource
## Data-driven definition of an enemy spider. Slice 1 ships one of these with no
## skills; "specialised spiders as you descend" later means authoring new
## resources and honouring `skills`, not rewriting the enemy scene (design §5).

@export var display_name: String = "Rival Spider"
@export var max_health: float = 80.0
@export var move_speed: float = 85.0
## Hunger gained per second (before depth scaling).
@export var hunger_rate: float = 3.0
## Animated art, set once SpriteCook assets exist. Optional for slice 1.
@export var sprite_frames: SpriteFrames
## Active skills — empty in slice 1; the extension seam for specialisation.
@export var skills: Array[StringName] = []

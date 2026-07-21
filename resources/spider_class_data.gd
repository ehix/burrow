class_name SpiderClassData
extends Resource
## Data-driven spider archetype — the specialisation analogue of EnemyType
## (design §3). Concrete classes (Net-Caster, Wolf, Weaver, Decoy) are
## authored as `.tres` resources under `resources/spiders/` referencing this
## schema plus their skill scenes, not subclasses — the same "author a
## Resource, don't rewrite the scene" pattern EnemyType already established.

enum SpiderClass { NET_CASTER, WOLF, WEAVER, DECOY }

@export var spider_class: SpiderClass
@export var display_name: String = ""
## Sprite tint while this class is active — Player.apply_class()/
## Enemy._apply_class() apply it to the spider's sprite.
@export var display_color: Color = Color.WHITE
## Ambush/Melee focus (Net-Caster, Weaver) multiplies this up; Ranged focus
## (Decoy) multiplies it down. 1.0 = the slice-1 baseline.
@export var melee_damage_mult: float = 1.0
## Net-Caster disables standard web shooting entirely in favour of its Net
## Projectile skill.
@export var web_enabled: bool = true
@export var web_fire_rate_mult: float = 1.0
@export var web_projectile_speed_mult: float = 1.0
## Direct health cost to the shooter on a successful fire (0.0 = free, the
## default for every class but Decoy).
@export var web_fire_health_cost: float = 0.0
## Skill scenes this class can activate, in kit order. Each scene's root
## script must extend SkillComponent.
@export var skill_scenes: Array[PackedScene] = []

## Baked directional art at the high three-quarter oblique camera angle
## (docs/art-bible.md §2) -- replaces the old single-sprite in-engine-
## rotation approach, which only worked under a flat top-down camera (see
## §2's 2026-07-21 revision for why rotation can't fake this camera angle).
## No separate EAST texture: generating two independently-consistent mirror
## poses proved unreliable across every class but Warden (west/east often
## read as "walking backwards" even after swapping which file played for
## which direction -- the pose itself, not the label, was the problem).
## EAST is always SOUTH/WEST's own texture rendered with Sprite2D.flip_h,
## guaranteeing a true mirror by construction instead of by generation luck.
## Player.apply_class()/Enemy._apply_class() and every `facing` update pull
## the matching frame + flip through frame_for_facing()/should_flip_h().
@export var sprite_south: Texture2D
@export var sprite_north: Texture2D
@export var sprite_west: Texture2D


## Which baked directional frame matches `facing`. `facing` is always
## exactly one of the 4 cardinal unit vectors by the time this is called --
## Player._dominant_dir() and Enemy._dominant() both reduce all movement
## input to a single cardinal direction before `facing` is ever assigned --
## so an exact match is sufficient, no angle bucketing needed. Falls back to
## `sprite_south` for the Vector2.ZERO case (the pre-movement default).
## RIGHT reuses sprite_west -- see should_flip_h().
func frame_for_facing(facing: Vector2) -> Texture2D:
	if facing == Vector2.RIGHT or facing == Vector2.LEFT:
		return sprite_west
	if facing == Vector2.UP:
		return sprite_north
	return sprite_south


## True when the frame frame_for_facing() returned needs to be mirrored to
## match `facing` -- currently just RIGHT, since sprite_west is authored
## facing left and reused directly (unflipped) for LEFT.
func should_flip_h(facing: Vector2) -> bool:
	return facing == Vector2.RIGHT

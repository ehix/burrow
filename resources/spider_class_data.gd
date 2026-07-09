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
## Ambush/Melee focus (Net-Caster, Weaver) multiplies this up; Ranged focus
## (Decoy) multiplies it down. 1.0 = the slice-1 baseline.
@export var melee_damage_mult: float = 1.0
## Net-Caster disables standard web shooting entirely in favour of its Net
## Projectile skill.
@export var web_enabled: bool = true
@export var web_fire_rate_mult: float = 1.0
@export var web_projectile_speed_mult: float = 1.0
## Skill scenes this class can activate, in kit order. Each scene's root
## script must extend SkillComponent.
@export var skill_scenes: Array[PackedScene] = []

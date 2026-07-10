class_name UpgradeCatalog
extends Resource
## One permanent, rune-purchased upgrade entry (design §5: Economy). Concrete
## upgrades are authored as `.tres` resources listing an id/cost/description;
## `GameState.buy_upgrade()` is the only spend path. "Permanent" here means
## session-long, the same guarantee `GameState.player_wins`/`enemy_wins`
## already make — true cross-session persistence needs a save system, which
## doesn't exist yet in this project and is out of scope here.

@export var upgrade_id: StringName
@export var display_name: String = ""
@export var description: String = ""
@export var rune_cost: int = 100
## Which of the player's stats this upgrade permanently boosts, and by how
## much (Player.refresh_upgrades() applies it). A negative amount lowers the
## stat — used for "smaller is better" ones like hunger_rate/web_fire_rate's
## underlying cooldown.
@export_enum("max_health", "melee_damage", "web_fire_rate", "hunger_rate") var effect_stat: String = "max_health"
@export var effect_amount: float = 10.0

class_name PreyType
extends Resource
## Data-driven prey archetype — the edible-creature analogue of EnemyType
## (design §6). Concrete variants (Normal/Fungal Larva, Beetle, Ant, Cicada
## Nymph) are authored as `.tres` resources under `resources/prey/`, not new
## scripts, mirroring how `resources/enemies/rival_spider.tres` is authored
## rather than subclassed.

@export var display_name: String = "Larva"
## Hunger removed via HungerComponent.satiate() on consumption.
@export var hunger_value: float = 40.0
## False marks a hazard/obstacle creature (Centipede) that cannot be eaten at
## all — melee/web interactions with it never call satiate().
@export var edible: bool = true
## Status effect applied to the eater via its StatusEffectComponent on
## consumption. Empty id = no status hook (Normal Larva). Beetle's flat
## armor mitigation is `&"armor"`; Ant's speed boost is `&"seed_haste"` (reuses
## Seed Pod's tag); Fungal Larva's poison is `&"venomous"` (reuses Fungus
## Poison's tag — see FungusPoisonItem.apply_venom_on_hit(), not yet wired
## into Enemy/Player's own eat call sites).
@export var on_eaten_status_id: StringName = &""
@export var on_eaten_magnitude: float = 0.0
@export var on_eaten_duration: float = 0.0
## Cicada Nymph [Rare]: consuming it spawns a radial reveal ping instead of
## (or alongside) a status hook — see EventBus.location_revealed.
@export var reveals_location: bool = false

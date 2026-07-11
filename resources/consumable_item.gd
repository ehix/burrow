class_name ConsumableItem
extends Resource
## Base for a pickup/deploy world item (Lure, Fungus variants, Seed Pod —
## design §5). A world pickup scene calls `apply(consumer)` on overlap (or, for
## a deployable like Lure, on placement) then frees itself. Concrete items
## reach into the consumer's StatusEffectComponent/HungerComponent/GridMover
## siblings the same way SkillComponent subclasses do.

## Placeholder color-per-item_id, shared by WorldItemPickup's world dot and
## Player's held-item indicator — no art assets yet (design: item/inventory
## rework).
const ITEM_COLORS := {
	&"fungus_poison": Color(0.55, 0.25, 0.65, 0.9),
	&"fungus_sense": Color(0.3, 0.75, 0.55, 0.9),
	&"seed_pod": Color(0.85, 0.7, 0.25, 0.9),
	&"lure": Color(0.6, 0.85, 1.0, 0.9),
}

@export var item_id: StringName
@export var pickup_radius: float = 20.0


## Override in subclasses. `consumer` is the spider (or larva, for Lure) that
## picked it up or triggered it.
func apply(_consumer: Node) -> void:
	pass

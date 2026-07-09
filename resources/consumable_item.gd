class_name ConsumableItem
extends Resource
## Base for a pickup/deploy world item (Lure, Fungus variants, Seed Pod —
## design §5). A world pickup scene calls `apply(consumer)` on overlap (or, for
## a deployable like Lure, on placement) then frees itself. Concrete items
## reach into the consumer's StatusEffectComponent/HungerComponent/GridMover
## siblings the same way SkillComponent subclasses do.

@export var item_id: StringName
@export var pickup_radius: float = 20.0


## Override in subclasses. `consumer` is the spider (or larva, for Lure) that
## picked it up or triggered it.
func apply(_consumer: Node) -> void:
	pass

extends Node
## Global, typed signal hub. Decouples entities from World/HUD/GameState.
##
## Nothing here holds state — it only relays. Emitters call
## EventBus.<signal>.emit(...); listeners connect in _ready().
## See the Burrow rebuild design §4 for the authoritative signal set.

## A larva entered a trap's area and became caught.
signal larva_trapped(larva: Node, trap: Node)

## A spider consumed a caught larva. `overflow` is how far the meal pushed the
## consumer's hunger past full (>= 0); feeds future power boosts.
signal larva_consumed(by: Node, overflow: float)

## Stub for slice 1: a consumer ate while already full. Emitted, ignored for now.
signal excess_consumed(by: Node, amount: float)

## The enemy spider was removed from play. cause is "killed" or "starved".
signal enemy_defeated(cause: String)

## The player took damage this frame (for HUD flashes, sfx hooks).
signal player_damaged(amount: float)

## The player's health reached zero → permadeath.
signal player_died

## A hunger meter changed. `who` is the owning entity.
signal hunger_changed(who: Node, value: float, max_value: float)

## A health meter changed. `who` is the owning entity.
signal health_changed(who: Node, value: float, max_value: float)

## The run descended (or reset) to a new depth.
signal depth_changed(depth: int)

## GameState.runes changed (earned or spent). Design §5: Economy.
signal runes_changed(total: int)

## `who` switched between Level.Layer.GROUND and Level.Layer.CEILING (design
## §1: Dual-Plane Map Architecture). `plane` is a Level.Layer value.
signal plane_changed(who: Node, plane: int)

## A world hazard fired (design §7). `hazard_name` is e.g. "water_ingress",
## "seismic_compaction", "centipede_express".
signal hazard_triggered(hazard_name: String)

## Dev tool (Q): the player's active spider class changed (design §3).
## `spider_class` is a SpiderClassData.SpiderClass value.
signal class_changed(spider_class: int)

## A timed status effect (Poison, Speed, Sense, Armor, ...) was applied to or
## expired on `who`, via its StatusEffectComponent.
signal status_effect_applied(who: Node, id: StringName, magnitude: float, duration: float)
signal status_effect_expired(who: Node, id: StringName)

## `who` consumed a Cicada Nymph [Rare] — a radial ping should reveal their
## position (design §6).
signal location_revealed(who: Node)

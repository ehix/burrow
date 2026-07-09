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

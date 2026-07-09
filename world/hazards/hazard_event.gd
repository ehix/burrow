class_name HazardEvent
extends RefCounted
## Base for a scheduled world event that HazardDirector ticks (design §7:
## Dynamic Environment Seeding). Each hazard owns its own severity constants
## (fixed, not depth-scaled — HazardDirector scales trigger *frequency*
## instead) and decides for itself what triggering means against a Level.

var min_depth: int = 1


## Override in subclasses. Called by HazardDirector when this hazard's timer
## fires and GameState.depth >= min_depth.
func trigger(_level: Node) -> void:
	pass

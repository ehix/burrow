class_name EnemyUtilityAI
extends RefCounted
## Scores candidate actions each decision tick and returns the highest-scoring
## one (design §2: Intelligent Enemy AI Matrix). Sits above Enemy's existing
## enum FSM: `State` remains the execution mechanism, and CHASE/FLEE's hard
## overrides in `Enemy._update_state` stay authoritative safety rails — this
## only arbitrates the "soft" choices (PATROL vs SEEK_FOOD vs offering a class
## skill) once an enemy has a SpiderClassData kit to draw skills from. Not yet
## consulted by Enemy in this pass.

enum Action { PATROL, SEEK_FOOD, CHASE, FLEE, USE_SKILL }

class Candidate:
	var action: Action
	var score: float
	var context: Dictionary

	func _init(p_action: Action, p_score: float, p_context: Dictionary = {}) -> void:
		action = p_action
		score = p_score
		context = p_context


## depth_intel in [0, 1]: how "smart"/aggressive the enemy plays at this
## depth. Callers use it to bias skill-use weight and shrink
## Enemy.repath_interval (faster replanning) — never to change health/damage
## numbers directly. Those stay on EnemyType/GameState.depth_scale(), so
## intelligence scaling alone can never compound into an impossible fight
## (guardrail).
static func depth_intel(depth: int, max_depth_for_scaling: int = 20) -> float:
	return clampf(float(depth) / float(max_depth_for_scaling), 0.0, 1.0)


static func best(candidates: Array[Candidate]) -> Candidate:
	var winner: Candidate = null
	for c in candidates:
		if winner == null or c.score > winner.score:
			winner = c
	return winner

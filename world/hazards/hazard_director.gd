class_name HazardDirector
extends Node
## Schedules Water Ingress, Seismic Compaction, and Centipede Express against
## the Level it's bound to. Depth scales *frequency* only, via
## GameState.depth_scale() — each hazard's own severity constants stay fixed,
## so a deep run gets hazards more often, never a single hazard that's
## unfairly more severe (guardrail: no impossible encounters). Instanced by
## Level.build() and bound to itself.

const WATER_INGRESS_BASE_INTERVAL := 50.0
const SEISMIC_BASE_INTERVAL := 70.0
const CENTIPEDE_BASE_INTERVAL := 120.0

var _level: Node
var _hazards: Array[HazardEvent] = []
var _base_intervals: Array[float] = []
var _timers: Array[float] = []


func bind_level(level: Node) -> void:
	_level = level
	_hazards = [WaterIngress.new(), SeismicCompaction.new(), CentipedeExpress.new()]
	_base_intervals = [WATER_INGRESS_BASE_INTERVAL, SEISMIC_BASE_INTERVAL, CENTIPEDE_BASE_INTERVAL]
	_timers = _base_intervals.duplicate()


func _process(delta: float) -> void:
	if _level == null or GameState.freeze_others:
		return
	for i in _hazards.size():
		_timers[i] -= delta
		if _timers[i] <= 0.0:
			# Faster at depth: frequency scales with depth_scale(); severity does not.
			_timers[i] = _base_intervals[i] / GameState.depth_scale()
			if GameState.depth >= _hazards[i].min_depth:
				_hazards[i].trigger(_level)


## Fire one random eligible (depth-gated) hazard immediately and reset its
## schedule — the base intervals (50-120s) are far too slow to exercise
## interactively otherwise. Dev tool (H), see World._dev_trigger_hazard.
func trigger_random_now() -> void:
	if _level == null or _hazards.is_empty():
		return
	var eligible: Array[int] = []
	for i in _hazards.size():
		if GameState.depth >= _hazards[i].min_depth:
			eligible.append(i)
	if eligible.is_empty():
		return
	var i: int = eligible[randi() % eligible.size()]
	_hazards[i].trigger(_level)
	_timers[i] = _base_intervals[i] / GameState.depth_scale()

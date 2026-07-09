class_name HazardDirector
extends Node
## Schedules Water Ingress, Seismic Compaction, and Centipede Express against
## the Level it's bound to. Depth scales *frequency* only, via
## GameState.depth_scale() — each hazard's own severity constants stay fixed,
## so a deep run gets hazards more often, never a single hazard that's
## unfairly more severe (guardrail: no impossible encounters). Not yet
## instanced by Level/World in this pass — attach as a child of Level and call
## `bind_level(level)` to wire it in.

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

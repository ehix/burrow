class_name CentipedeExpress
extends HazardEvent
## An apex centipede runs a straight line across the maze, carving a fresh
## corridor: opens every wall tile along a random horizontal or vertical
## sweep, skipping the boundary (guardrail). Unlike Seismic Compaction (net-
## neutral), this hazard only ever adds tunnel, never removes one. A real
## Centipede then rides its own fresh corridor (Level.spawn_centipede_along())
## -- the hazard's name stops being purely metaphorical.

func trigger(level: Node) -> void:
	if level == null or level.maze == null:
		return
	var maze: MazeData = level.maze
	var line: Array[Vector2i] = []
	if randi() % 2 == 0:
		var y := 1 + randi() % maxi(1, maze.height - 2)
		for x in maze.width:
			if not maze.is_boundary(x, y):
				level.dev_remove_wall_at(Vector2i(x, y))
				line.append(Vector2i(x, y))
	else:
		var x := 1 + randi() % maxi(1, maze.width - 2)
		for y in maze.height:
			if not maze.is_boundary(x, y):
				level.dev_remove_wall_at(Vector2i(x, y))
				line.append(Vector2i(x, y))
	level.spawn_centipede_along(line)
	EventBus.hazard_triggered.emit("centipede_express")

class_name CentipedeExpress
extends HazardEvent
## An apex centipede bursts in through one boundary edge and crawls in a
## straight line clear across the maze to the opposite edge (Level.
## spawn_centipede_express_rider() / CentipedeExpressRider), carving open
## whatever wall stands in its way, destroying larvae/traps/items, and
## shoving any spider caught in its path -- a quick, disruptive pass through
## the environment rather than a permanent obstacle (unlike the seeded
## obstacle Centipede, this one always keeps moving and frees itself once
## it's fully exited the far side).

func trigger(level: Node) -> void:
	if level == null or level.maze == null:
		return
	var maze: MazeData = level.maze
	var horizontal := randi() % 2 == 0
	var forward := randi() % 2 == 0
	var entry: Vector2i
	var direction: Vector2i
	var steps: int
	if horizontal:
		var y := 1 + randi() % maxi(1, maze.height - 2)
		if forward:
			entry = Vector2i(1, y)
			direction = Vector2i.RIGHT
		else:
			entry = Vector2i(maze.width - 2, y)
			direction = Vector2i.LEFT
		steps = maze.width - 3
	else:
		var x := 1 + randi() % maxi(1, maze.width - 2)
		if forward:
			entry = Vector2i(x, 1)
			direction = Vector2i.DOWN
		else:
			entry = Vector2i(x, maze.height - 2)
			direction = Vector2i.UP
		steps = maze.height - 3
	level.spawn_centipede_express_rider(entry, direction, maxi(steps, 0))
	EventBus.hazard_triggered.emit("centipede_express")

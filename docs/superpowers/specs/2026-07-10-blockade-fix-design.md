# Blockade Fix — Design

## Context

Playtest feedback (both the original raw feedback packet's Module 5 and a
live bug report) identified that Blockade is currently broken: triggering
it traps the caster inside their own barricade instead of placing it ahead
of them, it doesn't interact deliberately with whatever's on the target
tile, and it can be bypassed entirely via the ceiling plane. This fix is
being folded into the already-open class-identity-polish PR at the user's
explicit request, rather than split into its own PR — Blockade was
mentioned in that PR's scope only as a "Weaver immunity doesn't extend to
Blockade" clarification, but the actual mechanic fix belongs here now.

## Current state (confirmed bugs)

- `entities/skills/blockade_skill.gd`'s `_on_activate()` sets `blockade.
  global_position = origin.global_position` — the caster's own current
  position, not the tile ahead of them. Since the spawned `Blockade`
  (`entities/skills/scenes/blockade.gd`) is a `StaticBody2D` on the world
  collision layer, this leaves the caster physically overlapping a solid
  obstacle at their own tile — `GridMover`'s `test_move`-based blocking then
  reports every direction as blocked from that already-penetrating
  position, trapping the caster until a dev tool intervenes. Any other
  body already standing on that same tile (a larva, the enemy spider) is
  equally trapped, not deliberately interacted with.
- `Level.is_blocked(tile, plane)` (`world/level.gd:224-229`) is the single
  seam both `Player._blocked()`'s ground and ceiling checks route through:
  ground consults `maze.is_ground_blocked()`, ceiling consults a separate,
  static `CeilingData` overlay built once at maze generation. Neither
  branch has any awareness of a dynamically-placed `Blockade` — the
  physical `StaticBody2D` only ever affects ground movement (via
  `test_move`, the fallback after `is_blocked()` in `Player._blocked()`).
  A spider on the ceiling plane today passes straight over a Blockade
  underneath it, since ceiling blocking never touches physical colliders
  at all.
- `entities/skills/remove_walls_skill.gd`'s `_on_activate()` only ever
  calls `level.dev_remove_wall_at(target)` (carving an actual maze wall
  tile) — it has no awareness of Blockades and cannot destroy one.
- `Blockade.take_hit()` (`entities/skills/scenes/blockade.gd`) is already
  correctly wired to melee (`Player._melee`, `entities/player/player.gd:
  314-319`) and both web-shot variants (`WebShot._on_body_entered`,
  `NetShot._on_body_entered`) — these two "attacks" already work today and
  are unaffected by this fix.
- `WebTrap.tile_has_caught_web()` (`entities/web/web_trap.gd`) is the
  established pattern for "is there a live X at this tile" static helpers
  consulted from elsewhere — this fix adds an equivalent for `Blockade`.
- `GridMover.spider_tile_contested()` (`components/grid_mover.gd:66-79`)
  is the established pattern for "does another spider already occupy this
  tile," using each spider's own `GridMover.committed_tile()` — this fix
  reuses the same idiom to check for the enemy spider before placement.
- `Larva.web_kill()` (`entities/larva/larva.gd`) is the established
  "killed, not eaten, leaves an inedible corpse, removed from the `larvae`
  group" path — exactly what "crushed and killed" means for a larva caught
  under a newly-placed Blockade.
- `Level.tile_of(world) -> Vector2i` and `Level.centre_of(tile) ->
  Vector2` (`world/level.gd:120-125`) are the existing public grid/world
  conversion helpers this fix reuses for computing and snapping to the
  forward tile — the same pair `NetHoldSkill._forward_tile_position()`
  already uses conceptually (there, via `GridMover.tile_size`; here, via
  `Level`, since `Level` is already looked up in `BlockadeSkill`
  for `patch_pit_at()`).

## Fix

### 1. Place ahead of the caster, snapped to grid

`BlockadeSkill._on_activate()` computes the target tile from the caster's
facing (duck-typed the same way every other skill already does:
`source.get("facing")`) instead of using the caster's own position:

```gdscript
func _on_activate(source: Node) -> void:
	if blockade_scene == null:
		return
	var origin := source as Node2D
	if origin == null:
		return
	var level := source.get_tree().get_first_node_in_group("level") as Level
	if level == null:
		return
	var facing: Vector2 = source.get("facing") if "facing" in source else Vector2.RIGHT
	var target_tile := level.tile_of(origin.global_position) + Vector2i(int(facing.x), int(facing.y))
	_crush_larva_at(target_tile, level)
	var blockade := blockade_scene.instantiate()
	_spawn_parent(source).add_child(blockade)
	blockade.global_position = level.centre_of(target_tile)
	if blockade.has_method("setup"):
		blockade.setup(hits_to_destroy)
	level.patch_pit_at(target_tile)
```

### 2. Can't be placed on the enemy spider; crushes a larva instead

`BlockadeSkill` overrides `activate()` (not just `_on_activate()`, mirroring
the established `NetHoldSkill`/`NetShotSkill` pattern of gating *before*
the base class charges cooldown/hunger) to refuse activating at all if the
target tile is occupied by another spider:

```gdscript
func activate(source: Node) -> bool:
	var origin := source as Node2D
	if origin == null:
		return false
	var level := source.get_tree().get_first_node_in_group("level") as Level
	if level == null:
		return false
	var facing: Vector2 = source.get("facing") if "facing" in source else Vector2.RIGHT
	var target_tile := level.tile_of(origin.global_position) + Vector2i(int(facing.x), int(facing.y))
	if _spider_occupies(target_tile, source):
		return false
	return super.activate(source)


func _spider_occupies(tile: Vector2i, source: Node) -> bool:
	for node in source.get_tree().get_nodes_in_group("spiders"):
		if node == source:
			continue
		var other := node as Node2D
		if other == null:
			continue
		var other_mover := other.get_node_or_null("GridMover") as GridMover
		if other_mover != null and other_mover.committed_tile() == tile:
			return true
	return false


func _crush_larva_at(tile: Vector2i, level: Level) -> void:
	for node in level.get_tree().get_nodes_in_group("larvae"):
		var larva := node as Node2D
		if larva != null and level.tile_of(larva.global_position) == tile and larva.has_method("web_kill"):
			larva.web_kill()
```

`activate()` and `_on_activate()` necessarily recompute the same
`target_tile` independently (the base `SkillComponent.activate()` contract
doesn't thread extra data through to `_on_activate()`) — this duplication
is minor and matches the existing codebase's tolerance for small
per-skill recomputation (e.g. `NetShotSkill` and `NetHoldSkill` each
independently resolve their own forward tile).

### 3. Blocks the ceiling plane too

`Level.is_blocked()` gets a Blockade-tile check that applies regardless of
plane, using a new static helper on `Blockade` mirroring `WebTrap.
tile_has_caught_web()`:

```gdscript
## world/level.gd
func is_blocked(tile: Vector2i, plane: Layer) -> bool:
	if maze == null:
		return true
	if Blockade.at_tile(get_tree(), tile, TILE_SIZE) != null:
		return true
	if plane == Layer.CEILING:
		return ceiling.is_blocked(tile.x, tile.y)
	return maze.is_ground_blocked(tile.x, tile.y)
```

```gdscript
## entities/skills/scenes/blockade.gd
## The live Blockade sitting on `tile`, or null. Returns the node (not just a
## bool) so callers that need to act on it — RemoveWallsSkill destroying it —
## don't have to re-scan the group a second time.
static func at_tile(tree: SceneTree, tile: Vector2i, tile_size: int) -> Blockade:
	var ts := float(tile_size)
	for node in tree.get_nodes_in_group("blockades"):
		var blockade := node as Blockade
		if blockade == null:
			continue
		var blockade_tile := Vector2i(int(floorf(blockade.global_position.x / ts)), int(floorf(blockade.global_position.y / ts)))
		if blockade_tile == tile:
			return blockade
	return null
```

`Level.is_blocked()` then checks `Blockade.at_tile(get_tree(), tile, TILE_SIZE) != null`. This makes ground-plane blocking redundant-but-harmless (a Blockade tile
was already physically blocked via `test_move`; now it's also reported by
`is_blocked()`, which changes nothing observable there) while genuinely
fixing ceiling-plane blocking, which previously never consulted physical
colliders at all.

### 4. Remove Walls can also destroy a Blockade

`RemoveWallsSkill._on_activate()` checks for a Blockade at its target tile
first; if one is there, it destroys it outright instead of attempting to
carve a wall (a Blockade always sits on an already-open floor tile, so
`dev_remove_wall_at` would find nothing to carve there anyway):

```gdscript
func _on_activate(source: Node) -> void:
	var mover := source as Node2D
	if mover == null:
		return
	var level := source.get_tree().get_first_node_in_group("level") as Level
	if level == null or level.maze == null:
		return
	var facing: Vector2 = source.get("facing") if "facing" in source else Vector2.RIGHT
	var target := level.tile_of(mover.global_position + facing * float(Level.TILE_SIZE))
	var blockade := Blockade.at_tile(source.get_tree(), target, Level.TILE_SIZE)
	if blockade != null:
		blockade.destroy()
		return
	if level.is_boundary(target):
		return  # guardrail: the outer wall can never be destroyed this way
	level.dev_remove_wall_at(target)
```

Reuses the same `Blockade.at_tile()` static helper `Level.is_blocked()`
already calls — one tile-scan implementation, two call sites.

`Blockade` gains a `destroy()` method — an explicit, one-shot destruction
entry point distinct from `take_hit()`'s incremental-damage counter, since
Remove Walls is a single powerful action that should remove a Blockade
outright, not chip at its hit counter:

```gdscript
## entities/skills/scenes/blockade.gd
func destroy() -> void:
	queue_free()
```

This is the complete "destroy list": melee (`take_hit()`, already worked),
web shots (`take_hit()`, already worked), and now Remove Walls
(`destroy()`, new).

## Out of scope for this fix

- Any other skill in the Module 5 skills bundle (Sense, Camouflage,
  Hatchlings, Egg Mine, Silk Tunnel, Decoy) — those remain a separate,
  not-yet-started sub-project.
- Crushing anything other than larvae (e.g. Earthworm, which is already a
  static hard obstacle itself and not the "lesser insect" this feedback
  describes).

## Testing

- `BlockadeSkill._on_activate()` places the blockade at the tile ahead of
  the caster (not the caster's own tile), snapped to `Level.centre_of()`.
- `activate()` returns `false` and creates no blockade when another
  spider's `GridMover.committed_tile()` matches the target tile; returns
  `true` (and places one) when the target tile is clear.
- A larva standing on the target tile is killed (`web_kill()` — removed
  from the `larvae` group) when a blockade is placed there; a larva
  elsewhere is untouched.
- `Level.is_blocked()` reports blocked on both `Layer.GROUND` and
  `Layer.CEILING` for a tile with a live `Blockade`, and is unaffected by a
  freed (destroyed) one.
- `RemoveWallsSkill` destroys a `Blockade` on its target tile instead of
  attempting `dev_remove_wall_at`; with no blockade there, wall-carving
  behavior is unchanged from today (existing tests for this skill must
  keep passing).
- `Blockade.destroy()` frees the node unconditionally, regardless of
  `_hits`/`hits_to_destroy` state.
- Manual verification in a running Godot session (headless boot/scene
  smoke test per the project's Godot validation workflow): trigger
  Blockade facing an open tile and confirm it appears ahead, not underfoot,
  and the caster is never trapped; trigger it facing the enemy spider and
  confirm nothing is placed; trigger it facing a larva and confirm the
  larva dies and the blockade still appears; confirm a spider on the
  ceiling can no longer cross a placed Blockade's tile; confirm Remove
  Walls destroys a placed Blockade in one use.

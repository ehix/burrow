# burrow

### Overview
#### Ultimate scope
- Type of slither.io, multiplayer, multiplatform game.
- Top-down 2D Maze of randomised tunnels:
	- Sort of like Bomberman, but asymmetric.
- The aim is to kill or starve the competing spider(s).
- Smaller creatures wander the tunnels/cross between walls and can be caught/consumed.
- Visibility in the maze is limited to the area around the spider, fog of war style.
- The spider advances/burrows down into the 2D plane once the opponent is defeated.
- Greater spiders have chance to specialise the further they get:
	- Although subject to permadeath; if defeated, they start again from scratch.

### Spiders
#### Functionally
- Only see a limited distance ahead in the tunnel.
- Shoot a web (attack) over a limited distance ahead in the tunnel.
- Lay a limited number of traps to catch creatures.

#### Cosmetically
- Are customisable.
- Basic creator, shape and colour options.
        
#### Trap mechanics
- Other spiders can't cross traps left by others.
- Other spiders can collect/consume trapped creatures left by others.
- Consuming trapped creatures satiates hunger:
	- Prevents loss of health.
	- Could prevent loss of movement speed.
	- Consuming excess creatures boosts power:
		- Rarely (as addition to common - every 1/5): 
			- Ability to break walls.
		- Commonly (every 1):
			- Visability.
			- Firepower range and damage.
			- Number of traps that can be laid at one time.
            
### Progression
- Size/dimensions of map increases/decreases.
- Scarcity and abundance of consumable creatures changes.
- Water temporarily flows through sections of the structure.
- More players in session/on map.
#### Classes
- Specialisation classes/tiers offered after each successful game
##### Current ideas
1. Allow spider to lay eggs: 
	- Release tiny quick moving spiders to attack the enemy/scout cavern.
2. Coat tunnel in silk:
	- Slows enemy movement for a fixed amount of time.
3. Camouflage:
	- Player spider opacity increased temporarily.

---

## Development (Godot 4.7 rebuild — slice 1)

The playable project lives at the repo root (`project.godot`). The Godot 3.x
prototype has been retired now that the slice 1 and slice 2 rebuild has
superseded it.

Full design: [`docs/superpowers/specs/2026-07-06-burrow-rebuild-design.md`](docs/superpowers/specs/2026-07-06-burrow-rebuild-design.md).

### Run

1. Open the project in **Godot 4.7** (GDScript only, no Mono needed).
2. Press Play — `world/world.tscn` is the main scene.

Controls: **WASD / arrows** move, **Space** fires a web shot along your facing,
**E** lays a trap. Clear the enemy (kill or starve it) to burrow to the next
depth; HP + Hunger carry forward. Die and it's permadeath back to depth 1.

### Art

All sprites/tilesets are being regenerated in **SpriteCook**. Until then,
entities render as flat placeholder `Polygon2D` shapes and the maze draws as
flat floor/wall rects (`world/maze/maze_renderer.gd`) — swap in a `TileMapLayer`
once the tileset exists; the collision / occluder / navigation pipeline is built
separately from the maze grid, so it is unaffected.

World/character/creature/item reference for art generation:
[`docs/art-bible.md`](docs/art-bible.md).

### Tests

Pure-logic tests (maze generation, tile classification, health, hunger, trap
resolution) live in `tests/` and use **GUT**. Install GUT from the AssetLib
(`addons/gut/`), then run the suite from the GUT panel or:

```
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```


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

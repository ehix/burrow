# Burrow — Art Bible & World Reference

A single reference for generating consistent art (sprites, tilesets, VFX) for
*Burrow*. Written for two audiences at once: a human skimming for the vibe,
and an AI art tool that needs concrete facts (species, color, size, pose) to
generate from. Everything under "Confirmed" is pulled straight from the
game's code and existing reference art — treat it as ground truth. Everything
under "Suggested direction" is a proposed creative choice the game doesn't
yet lock in; adjust freely, but keep the doc updated once you do, so future
generations stay consistent with each other.

---

## 1. Elevator pitch

*Burrow* is a top-down, fog-of-war maze game about spiders. You control a
spider in a procedurally-generated tunnel system, hunting or starving a
rival spider while eating smaller prey creatures to stay alive. Win, and you
literally **burrow down** — the current maze collapses behind you and a
fresh, harder one opens up one level deeper. Lose, and it's **permadeath**:
back to depth 1, from scratch. The tunnels themselves fight back the deeper
you go: floods, earthquakes, and a giant apex centipede blast through the
same corridors you're hunting in.

It's dirt, dark, and grubs — not a cute bug game. Think real arachnid
anatomy and a genuinely underground palette, not a cartoon mascot spider.

## 2. Established art style

Seven reference sprites already exist (`assets/sprites/`) and set the house
style. Match this, don't reinvent it:

- **Semi-realistic pixel/vector illustration** — detailed, soft-edged,
  anti-aliased outlines, not blocky 8-bit/retro pixel art. Fine linework
  (see `web_trap.png`'s hand-drawn web strand detail) is in-style.
- **Real arachnid/invertebrate anatomy**, not a cartoon/mascot reinterpretation
  — correct leg count and joints, correct body segmentation. The rival
  spider is explicitly a **trapdoor spider** silhouette
  (`enemy_trapdoor_spider.png`); the Wolf Spider class sprite
  (`player_wolf_spider.png`) is a recognizable, naturalistic wolf spider.
- **Muted, earthy, desaturated palette** on the creatures themselves — browns,
  tans, near-blacks, olive. Saturated color is reserved for *meaning*
  (class identity, status effects, hazards — see §3) rather than the base
  creature rendering. A creature's "natural" coloring should read as
  camouflaged-into-dirt; the *accent* color (class tint, item glow) is what
  pops.
- **Top-down "resting" pose**, legs spread naturally, viewed roughly from
  directly above with a slight illustrative tilt — not a strict orthographic
  flat-top view. No walk cycle needed: sprites are rotated in-engine to face
  the direction of travel (`Player._process`, `player.gd:123-124`), so one
  good top-down pose per creature is enough.
- **Sizes so far are not on a strict pixel grid** — existing sprites range
  91×92 to 126×126px, scaled to fit gameplay rather than authored to a fixed
  canvas. The maze's own grid unit is **48×48px** (`Level.TILE_SIZE`). A
  creature occupying one tile should read clearly at roughly that size once
  placed in-world; bigger multi-tile things (the Centipede) are built from
  repeated 48×48 segment tiles instead of one large sprite.
- **No directional/rotational asymmetry** in a sprite's silhouette — since
  the engine rotates the whole sprite to face travel direction, an
  asymmetric "always faces this way regardless of rotation" design element
  (like a fixed logo on the back) would rotate incorrectly. Keep creature art
  radially neutral (a spider works fine here — legs radiate outward).

## 3. Color language

Colors in *Burrow* are a coding system, not decoration — the **same hue
means the same thing everywhere** it appears (an item, its status-effect
icon, and any in-world marker of that effect all share one color family).
Preserve this when generating new art; it's how a player learns the game
without reading text.

### Environment base palette (earthy/dark)

| Element | RGB (float) | Hex | Notes |
|---|---|---|---|
| Floor — ground plane | `0.17, 0.15, 0.13` | `#2B2621` | dark warm umber |
| Floor — ceiling plane | `0.13, 0.17, 0.24` | `#212B3D` | dark cool blue-slate; floor recolors when *you* are on the ceiling |
| Wall | `0.31, 0.27, 0.23` | `#4F453B` | warm taupe/dirt-brown, same on both planes |
| Natural pit | `0.15, 0.08, 0.05` | `#26140D` | near-black dirt hole |
| Water (flood hazard) | `0.15, 0.45, 0.75` | `#2673BF` | clear medium blue — deliberately distinct from the pit's brown |
| Ambient darkness (fog of war) | `0.05, 0.05, 0.07` | `#0D0D12` | near-black with a faint blue-violet cast |
| Sense reveal outline | `0.75, 0.9, 1.0` | `#BFE6FF` | pale cyan-white "x-ray" highlight, never a filled/lit patch |
| Seismic Compaction dust puff | `0.4, 0.35, 0.3` | `#66594C` | brief expanding dust cloud |

### Class identity colors (spider tint)

| Class | RGB (float) | Hex |
|---|---|---|
| Net-Caster | `0.85, 0.75, 0.35` | `#D9BF59` gold/amber |
| Wolf Spider | `0.85, 0.4, 0.25` | `#D96640` orange-red |
| Weaver | `0.4, 0.75, 0.45` | `#66BF73` green |
| Decoy | `0.65, 0.45, 0.85` | `#A673D9` purple |

### Item / status-effect colors (one hue, two contexts)

| Meaning | RGB (float) | Hex | Appears as |
|---|---|---|---|
| Venomous / poison (Fungus Poison) | `0.55, 0.25, 0.65` | `#8C40A6` plum/violet | item pickup + "venomous" status icon |
| Poison damage-over-time | `0.5, 0.8, 0.3` | `#80CC4C` yellow-green | DoT tick status icon |
| Sense (Fungus Sense) | `0.3, 0.75, 0.55` | `#4CBF8C` teal | item pickup + "sense" status icon |
| Haste / speed (Seed Pod) | `0.85, 0.7, 0.25` | `#D9B240` mustard/gold | item pickup + "seed_haste" status icon |
| Silk haste (Weaver self-buff) | `0.6, 0.85, 1.0` | `#99D9FF` pale sky blue | status icon only |
| Lure | `0.6, 0.85, 1.0` | `#99D9FF` pale sky blue | pulsing ring + pickup |
| Camouflage | `0.6, 0.75, 1.0` | `#99BFFF` pale blue | outline while active |
| Decoy effigy | `0.6, 0.6, 0.65` | `#9999A6` grey-lavender | translucent silhouette |

### Other

| Element | RGB (float) | Hex |
|---|---|---|
| Centipede body segment | `0.3, 0.45, 0.2` | `#4C7333` dark olive-green |
| Blockade (Weaver's rock/dirt barrier) | `0.35, 0.25, 0.15` | `#594026` dark dirt brown |
| Damage flash | `1.0, 0.35, 0.35` | red |
| Melee slash VFX | `1.0, 0.95, 0.85` | warm near-white |

**Rule of thumb for new assets:** natural body = desaturated earth tone;
anything meaningful (class, item, hazard, effect) = one clear saturated hue
from the tables above, reused consistently.

## 4. World & setting

An underground network of **randomized tunnel mazes**, rendered top-down.
Visibility is limited to a lit radius/cone around the player (fog of war) —
darkness is the default state; light is earned, not given. Each depth is a
fresh maze, not a new location: the fiction is that you're **burrowing
straight down** through the earth, one collapsing/regenerating layer at a
time. There is no persistent geography above depth 1 — every run starts
there again.

The tunnels are alive and hostile independent of the rival spider:

- **Water Ingress** — floods a patch of tunnel outward from a random point,
  ring by ring, then recedes the same way (outermost ring first out,
  origin last). Reads as tunnels flash-flooding and slowly draining.
- **Seismic Compaction** — a small earthquake: some walls collapse open into
  new floor, some floor collapses shut into new wall, in the same event.
  The maze's layout is never fully static.
- **Centipede Express** — an apex centipede bursts through one edge of the
  map and drives a straight line clear across it, carving a fresh corridor
  through solid wall as it goes, before exiting the far side. A visceral,
  disruptive event, distinct from the slow, stationary regular Centipede.

There's a fungal ecosystem growing in the dark (two mushroom/fungus pickups,
poisonous and sense-granting — see §7), and the game's currency is literally
called **runes** — a light arcane-underground flavor hook, currently
unelaborated visually, but worth leaning into for UI/currency iconography
(carved sigils, glowing dirt-etched glyphs) if you want a visual motif there.

**Tone in one line:** dim, dirt-brown, dangerous, and quietly hostile — nature
red in tooth and claw, not spooky-cute.

## 5. Spiders — player classes & the rival

Every spider (player or rival) is the same underlying creature type,
distinguished by a **class** (their species/build) and a **class tint**
(§3) applied to their sprite. The rival spider is mechanically identical
to the player — same four classes, same skills, same stat kit — so it
should read as a *mirror*, not a separate monster. It's currently anchored
to a **trapdoor spider** silhouette in the one reference sprite that exists
(`enemy_trapdoor_spider.png`) — apt, since trapdoor spiders are real
burrow-and-ambush predators.

Each class in the fiction is one specific real spider species/archetype
(**suggested direction** — the code only fixes color + mechanics, not
species; adjust if you want, but keep it consistent across all art for that
class once chosen):

### Net-Caster — male — gold `#D9BF59`
**Suggested species: net-casting / ogre-faced spider** (real-world
*Deinopis*) — huge forward-facing eyes, holds a small rectangular web
between its front legs and throws it over prey. This maps directly onto its
kit: it can't fire a normal web shot at all, and instead **picks up any
placed trap and throws it as a fast, hard-hitting capture net**
(`Net Hold` / `Net Shot`). Heaviest melee hitter of the four classes.
Visual language for its net/projectile: a woven diamond, off-white fill
with a darker grey crosshatch (`#BFBFB2` fill, `#666659` lines).

### Wolf Spider — female — orange-red `#D96640`
Already explicitly a **wolf spider** (*Lycosidae*) in name — real wolf
spiders are famous for carrying their egg sac, then their newly-hatched
spiderlings, riding on their back/abdomen. That's a direct visual match for
her kit: she **plants a hidden egg-sac mine** that bursts into a swarm of
tiny spiderlings on trigger, and can **summon a small escort of aggressive
hatchling spiderlings** that scout ahead and attack. The hatchlings/mine
burst are small bright-red dots (`#D94D4D`); the mine itself is a small
drawn cocoon, brown (`#7F5933`).

### Weaver — male — green `#66BF73`
Code already calls this the **Funnel/Weaver spider** — real funnel-web
weavers spin a broad sheet web that narrows into a funnel retreat. Slower,
more deliberate web use than the others, but **immune to getting slowed by
webs himself**. His kit is architectural: **lays a line of web across
several tiles** (a literal funnel-web tunnel) and **drops a solid rock/dirt
barricade** to physically block a corridor. Barricade color: dark dirt-brown
(`#594026`).

### Decoy — female — purple `#A673D9`
The glass cannon: weakest melee, fastest/most frequent web-shooter, and
**pays her own health to fire**. Kit is stealth/misdirection: **turns
near-invisible** for a few seconds (breaks on landing or taking a hit), and
**drops a static decoy effigy** that draws rival aggro. **Suggested
species:** a spider built around camouflage/mimicry in real life — e.g. a
crab spider (ambush camouflage) or a ghost/huntsman spider (pale,
translucent-looking) would fit; avoid a species already used for another
class. Camouflage outline while active: pale blue (`#99BFFF`); the decoy
effigy itself is a dim, translucent grey-lavender silhouette (`#9999A6`).

## 6. Creatures

### Larva (base prey)
A small pale grub (`larva.png` — cream/off-white, simple segmented
shading) that wanders the tunnels cell to cell, reversing only at dead
ends. **Visibly grows the longer it survives** — up to 2.5× its spawn
size — and gets slower as it fattens. A bigger larva is worth more hunger
relief when eaten. If generating growth-stage variants, keep the same
silhouette/coloring and simply scale it, rather than redesigning it larger.

### Prey variants (same base grub, different "flavor")
Designed but not yet all illustrated — same base larva silhouette,
differentiated visually by whatever makes their effect legible at a glance:
- **Normal Larva** — the plain baseline (`larva.png`).
- **Fungal Larva** — grants "venomous" (plum `#8C40A6`) on eaten. Suggest a
  mottled/spotted variant, or one visibly infected with tiny fungal growths.
- **Beetle** — grants temporary armor on eaten. A distinct hard-shelled bug,
  not a grub — suggest a small dark, glossy-shelled beetle silhouette.
- **Ant** — grants a speed boost (mustard `#D9B240`) on eaten. A small,
  segmented, fast-looking ant silhouette.
- **Cicada Nymph [Rare]** — reveals a radius of the map on eaten. Should
  read as visibly rarer/more distinct than the others — larger, or with a
  subtle glow/translucency, since it's explicitly flagged rare in code.

### Centipede — the stationary obstacle
A **multi-segment obstacle creature**, not prey (can't be eaten). A chain of
identical dark-olive segments (`#4C7333`), each occupying one 48×48 tile,
laid head-first through a corridor — it physically blocks the tunnel on
both the ground and ceiling plane until driven off. When hurt enough it
flees toward the nearest map edge and burrows out tile-by-tile (segments
peel away as it exits, rather than vanishing instantly). Build this as a
single repeatable segment tile, not one long custom sprite — the engine
chains as many segments as the body needs.

### Centipede Express — the apex variant
The same segmented-worm visual language as the regular Centipede, but
**always moving, never stationary** — it bursts in through a tunnel wall
from the map's edge, drives a straight line clear across, and exits the far
side, carving fresh corridor and shoving anything in its path as it goes.
Should read as bigger/faster/more violent than the ordinary Centipede — an
apex predator variant of the same body plan, not a different creature
entirely. (Reuses the same segment tile; distinguish it primarily through
motion/behavior rather than needing a separate sprite.)

## 7. Items

Small world pickups, currently placeholder colored dots (7px radius) —
prime candidates for actual iconography. All colors match their
status-effect counterpart (§3):

| Item | Color | Fiction |
|---|---|---|
| **Fungus Poison** | plum `#8C40A6` | a poisonous mushroom/fungal growth; grants venomous attacks + poison DoT |
| **Fungus Sense** | teal `#4CBF8C` | a bioluminescent-feeling sense-granting fungus; triggers a free Sense pulse |
| **Seed Pod** | mustard `#D9B240` | a plant seed pod; temporary speed boost |
| **Lure** | pale sky blue `#99D9FF` | not eaten — deployed as a pulsing beacon that draws larvae toward it |

Suggested direction: lean into the "fungus" pair as literal mushrooms
growing in the dark (one visibly toxic-looking, one visibly glowing/spore-y),
the Seed Pod as an actual plant seed pod (unusual but not impossible
underground — a root vegetable pod, a fallen seed washed down by Water
Ingress), and the Lure as a pulsing organic beacon (an egg, a glowing lure
organ) rather than a mechanical device.

## 8. Environment / tileset

No tileset exists yet — the maze currently renders as flat colored
rectangles (`world/maze/maze_renderer.gd`). Base tile unit: **48×48px**.

Needed tile types, using the palette in §3:
- **Floor** (ground-plane color, `#2B2621`) and its **ceiling-plane**
  variant (`#212B3D`) — the *same* floor recolors depending which plane the
  viewer currently occupies, so these should feel like the same material
  under warm vs. cool lighting, not two different floor types.
- **Wall** (`#4F453B`) — identical on both planes.
- **Pit** marker (near-black `#26140D`) overlaid on floor — a natural hole.
- **Water** marker (`#2673BF`) overlaid on floor — a flood, visually
  distinct from the pit.

Autotiling shape set (`world/maze/tile_types.gd`) — standard tunnel/dungeon
topology, useful directly as a tileset shape list: a fully-enclosed blocked
cell; horizontal and vertical straight tunnels (which double as dead-ends);
four corner pieces; four T-junctions; one 4-way crossroads. 15 pieces total
if built as a classic wall-autotile set (or fewer if only floor/wall edges
need distinct art, since walls currently render as flat blocks with no
directional detail yet).

## 9. Hazard VFX

- **Water Ingress** — tunnels flood outward ring-by-ring from a point, then
  drain the same way in reverse (outer ring drains first, origin drains
  last). Should read as spreading-then-receding, not an instant flood.
- **Seismic Compaction** — a brief expanding dust puff (`#66594C`) marks a
  tile about to collapse into wall; some walls simultaneously crumble open
  elsewhere.
- **Centipede Express** — a straight-line wall-carving burst (see §6) —
  the environment's most violent, sudden event.
- **Combat** — a damage flash tints the hit target red (`#FF5959`); a melee
  swing draws a short warm near-white arc (`#FFF2D9`) at the point of
  impact.

## 10. UI status-effect color coding

The HUD's status-effect row uses the exact same hues as their source item —
keep any new status icon aligned to this table rather than picking a new
color:

| Status | Color |
|---|---|
| `sense` | teal `#4CBF8C` |
| `venomous` | plum `#8C40A6` |
| `poison` (DoT) | yellow-green `#80CC4C` |
| `silk_haste` | pale sky blue `#99D9FF` |
| `seed_haste` | mustard `#D9B240` |

## 11. Asset inventory

**Exist already** (`assets/sprites/`) — treat as the style anchor:
`player_wolf_spider.png` (92×92), `enemy_trapdoor_spider.png` (92×92),
`larva.png` (48×48), `web_shot.png` (40×40), `web_shot_spent.png` (76×76),
`web_trap.png` (116×116), `web_trap_spent.png` (126×126).

**Not yet made** (roughly in priority order for a maze that currently has
no tileset at all):
1. Floor/wall/pit/water tileset (§8) — biggest visible gap, everything else
   renders as flat rectangles right now.
2. The other three player/rival class sprites (Net-Caster, Weaver, Decoy) —
   only Wolf Spider exists.
3. Centipede body segment tile.
4. Item icons (Fungus Poison, Fungus Sense, Seed Pod, Lure) — currently
   plain colored dots.
5. Prey variants (Fungal Larva, Beetle, Ant, Cicada Nymph) — currently all
   render as the plain larva.
6. Skill VFX: Blockade barrier, Camouflage outline, Decoy effigy, Net
   Hold/Shot projectile, egg-mine cocoon, hatchling/mine-burst spiderlings.
7. Hazard VFX polish: flood water texture, compaction dust, Express
   carve-burst.

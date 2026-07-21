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

**Revised 2026-07-17** as part of the full art/animation pipeline reset
(`docs/superpowers/specs/2026-07-17-art-pipeline-design.md`): the style
direction below now targets SpriteCook's pixel-art mode, a deliberate pivot
away from this section's original semi-realistic direction — driven by
cost (pixel-mode generation is cheaper) as well as visual preference. The
seven existing reference sprites (`assets/sprites/`) no longer set the house
style; they are placeholders being fully replaced, not anchors to match.
Category 0 of the pipeline produces the first real style anchor under this
new direction.

- **Retro/indie pixel art** — crisp edges, grid-aligned, readable at small
  scale. This replaces the prior "semi-realistic, soft-edged, not blocky
  8-bit" direction; embracing a pixel-art look, not working around it. Fine
  linework where it reads clearly at pixel-art scale (see `web_trap.png`'s
  web-strand detail for the *kind* of silhouette detail worth keeping, not
  its soft-edged rendering) is still worth preserving.
- **Real arachnid/invertebrate anatomy**, not a cartoon/mascot reinterpretation
  — correct leg count and joints, correct body segmentation. The existing
  `enemy_trapdoor_spider.png` (a naturalistic trapdoor spider) and
  `player_wolf_spider.png` (a naturalistic wolf spider) are both good style
  anchors — the former is now Warden's own reference art (see §5), not a
  separate "enemy" species.
- **Muted, earthy, desaturated palette** on the creatures themselves — browns,
  tans, near-blacks, olive. Saturated color is reserved for *meaning*
  (class identity, status effects, hazards — see §3) rather than the base
  creature rendering. A creature's "natural" coloring should read as
  camouflaged-into-dirt; the *accent* color (class tint, item glow) is what
  pops.
- **Revised 2026-07-21 — high three-quarter oblique camera, not flat
  top-down:** viewed from above and slightly in front (roughly 60-70°
  above the horizon), matching the tilted faux-3D tunnel-wall rendering
  (`MazeRenderer`'s top-face/front-face two-tone blocks) rather than a
  strict orthographic bird's-eye view. First applied to a wolf-spider
  NSWE (North/South/East/West) directional sprite set. Superseds this
  section's earlier "directly above with a slight illustrative tilt"
  framing — the tilt is now a real, consistent camera angle, not just an
  illustrative flourish on an otherwise-flat pose.
- **Sizes so far are not on a strict pixel grid** — existing sprites range
  91×92 to 126×126px, scaled to fit gameplay rather than authored to a fixed
  canvas. The maze's own grid unit is **48×48px** (`Level.TILE_SIZE`). A
  creature occupying one tile should read clearly at roughly that size once
  placed in-world; bigger multi-tile things (the Centipede) are built from
  repeated 48×48 segment tiles instead of one large sprite.
- **Revised 2026-07-21 — directional/rotational asymmetry is now
  expected, not forbidden.** The old rule ("keep creature art radially
  neutral, since the engine rotates one sprite to face travel direction")
  only held under a flat top-down camera, where rotation is
  perspective-correct. Under the new oblique camera (previous bullet),
  rotating a single image would visibly rotate the camera tilt itself
  along with the character, which reads wrong — so a creature needs
  distinct baked poses per direction instead (NSWE: North/South/East/
  West, at minimum four; East/West can be mirror images of each other
  rather than separately authored). **This is an art-direction change
  only, not yet wired into the engine** — `Player._physics_process`
  (`player.gd:124`) and `Enemy._process` (`enemy.gd:589`) both still
  rotate a single sprite (`sprite.rotation = facing.angle()`); switching
  them to pick between baked directional frames instead is a separate,
  not-yet-scoped follow-up task once real NSWE art exists to wire in.

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

| Character | RGB (float) | Hex |
|---|---|---|
| Wolf | `0.85, 0.4, 0.25` | `#D96640` orange-red |
| Warden | `0.4, 0.75, 0.45` | `#66BF73` green |
| Ogre | `0.85, 0.75, 0.35` | `#D9BF59` gold/amber |
| Echo | `0.65, 0.45, 0.85` | `#A673D9` purple |

### Item / status-effect colors (one hue, two contexts)

| Meaning | RGB (float) | Hex | Appears as |
|---|---|---|---|
| Venomous / poison (Fungus Poison) | `0.55, 0.25, 0.65` | `#8C40A6` plum/violet | item pickup + "venomous" status icon |
| Poison damage-over-time | `0.5, 0.8, 0.3` | `#80CC4C` yellow-green | DoT tick status icon |
| Sense (Fungus Sense) | `0.3, 0.75, 0.55` | `#4CBF8C` teal | item pickup + "sense" status icon |
| Haste / speed (Seed Pod) | `0.85, 0.7, 0.25` | `#D9B240` mustard/gold | item pickup + "seed_haste" status icon |
| Silk haste (Warden self-buff) | `0.6, 0.85, 1.0` | `#99D9FF` pale sky blue | status icon only |
| Lure | `0.6, 0.85, 1.0` | `#99D9FF` pale sky blue | pulsing ring + pickup |
| Camouflage | `0.6, 0.75, 1.0` | `#99BFFF` pale blue | outline while active |
| Echo's decoy effigy | `0.6, 0.6, 0.65` | `#9999A6` grey-lavender | translucent silhouette |

### Other

| Element | RGB (float) | Hex |
|---|---|---|
| Centipede body segment | `0.3, 0.45, 0.2` | `#4C7333` dark olive-green |
| Blockade (Warden's rock/dirt barrier) | `0.35, 0.25, 0.15` | `#594026` dark dirt brown |
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

## 5. Spiders — the four characters

Four named characters, not four palette-swapped copies of one body. Each
gets its own species, silhouette, and design language grounded in its kit
— the class tint (§3) still applies as an accent, but it should read as
"this character's signature color," not the *only* thing telling them
apart. The rival is not a separate creature: it rolls one of these same
four characters at spawn, same as the player picks one — there's no
separate "enemy species" anymore (the old `enemy_trapdoor_spider.png`
reference sprite predates this and is superseded by Warden's own art, see
below).

### Wolf — female — orange-red `#D96640`
**Species: wolf spider (*Lycosa*).** Real wolf spiders carry their egg
sac, then their newly-hatched spiderlings, riding on their back/abdomen —
a direct match for her kit: she **plants a hidden egg-sac mine** that
bursts into a swarm of tiny spiderlings on trigger, and can **summon a
small escort of aggressive hatchling spiderlings** that scout ahead and
attack. Silhouette: robust, bristly, mottled-brown body, noticeably
stockier/more grounded than the other three — the "brawler" build.
Hatchlings/mine burst are small bright-red dots (`#D94D4D`); the mine
itself is a small drawn cocoon, brown (`#7F5933`).

### Warden — male — green `#66BF73`
**Species: trapdoor spider.** Real trapdoor spiders dig a burrow, silk-line
it, and seal it behind a hinged silk-and-soil door — a much closer match
for his kit than the old "funnel weaver" framing: **lays a line of web
across several tiles** (the silk-lined tunnel) and **drops a solid
rock/dirt barricade** to physically block a corridor (the door, generalized
to any corridor). Also **immune to getting slowed by webs himself** — he
lives in one. Silhouette: thick, shovel-like front legs (real trapdoor
spiders use these to dig), a squat, low-slung, burrow-dwelling body —
reads as a digger/builder, not a hunter. Barricade color: dark dirt-brown
(`#594026`).

### Ogre — male — gold `#D9BF59`
**Species: ogre-faced / net-casting spider (*Deinopis*).** Real ogre-faced
spiders hold a small rectangular net between their front legs and throw it
over prey — not a metaphor, literally his kit: can't fire a normal web
shot at all, instead **picks up any placed trap and throws it as a fast,
hard-hitting capture net** (`Net Hold` / `Net Shot`). Heaviest melee hitter
of the four. Silhouette: the species' namesake huge forward-facing eyes
(best night vision of any spider — he hunts in total darkness) and long,
stick-thin legs — should read as unmistakably different from Wolf's stocky
build even in silhouette alone. **Revised 2026-07-21 — net visual
language, rewritten after the original description read as a flat
geometric icon rather than real silk in practice:** fine, irregular
cribellate spider silk (real *Deinopis* net material), woven into a small
loose mesh — NOT a clean technical grid or fishing-net pattern.
Individual threads visible, crossing at slightly uneven, organic angles
rather than a perfect crosshatch. Fuzzy, faintly fluffy thread texture
(cribellate silk is combed into a woolly strand, unlike smooth
orb-weaver silk). Semi-transparent, with visible gaps between threads
especially near the edges. Soft, frayed, slightly irregular outline
rather than a crisp geometric border, with a gentle sag/give to its
shape since it's flexible silk held taut by the spider's legs, not a
rigid frame. Faint pale sheen on a few strands, subtle rather than shiny
or plastic-looking. Off-white/pale grey silk color (`#BFBFB2` base,
`#666659` shadow in the mesh gaps), roughly one to two body-lengths
across — small relative to the spider itself. Applies to both the held
net (`Net Hold`) and the thrown projectile (`Net Shot`).

### Echo — female — purple `#A673D9`
**Species: trashline/decoy orb-weaver (*Cyclosa*).** Real *Cyclosa* build
a life-sized fake decoy of themselves out of silk and debris in their web
so predators attack the decoy instead — literally her kit, not an
analogy: **drops a static decoy effigy** that draws rival aggro, and
**turns near-invisible** for a few seconds (breaks on landing or taking a
hit). Glass cannon: weakest melee, fastest/most frequent web-shooter, and
**pays her own health to fire**. Silhouette: many *Cyclosa* have unusual
spiky, elongated abdomens wrapped in silk-and-debris — lean into that for
a shape unlike any of the other three's normal round-bodied spider
silhouette, reinforcing that she's built around not-quite-being-there.
Camouflage outline while active: pale blue (`#99BFFF`); the decoy effigy
itself is a dim, translucent grey-lavender silhouette (`#9999A6`).

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

Superseded from the original "no tileset yet, flat colored rectangles"
plan below: floor, walls, and water tiles are textured, not flat-colored.
Base tile unit: **48×48px**.

Current materials (`assets/textures/`), each a single seamless-ish
generated image, tinted per the palette in §3 rather than baked per-plane
variants:
- **`floor_material.png`** — ground floor.
- **`wall_material.png`** — walls, identical on both planes.
- **`wet_floor_material.png`** / **`water_overlay_material.png`** — the
  flooded-tile base + animated overlay (see `WaterTileLayer`).

These aren't drawn as one continuously-tiled image (no autotile atlas, no
`tile_types.gd` shape set — that plan was superseded). Every tile draws an
independent, pseudo-randomly-cropped-and-flipped snapshot of its material
via `TileTextureVariant` (`world/maze/tile_texture_variant.gd`,
design: `docs/superpowers/specs/2026-07-20-tile-texture-variation-design.md`),
specifically so adjacent tiles don't show the exact same pixels — the
original per-tile draw calls (`draw_texture_rect(..., tile=true, ...)`)
always reset UV sampling to that draw call's own origin, so every tile of
a given material used to render pixel-identical.

### Constraints for generating a new/replacement material texture

Read this before generating a replacement for any of the four textures
above, or diagnosing one that "looks wrong" once wired in:

- **Same filename = zero code changes.** `TileTextureVariant` reads
  `texture.get_size()` live, never a hardcoded dimension — overwrite the
  existing PNG, re-run the headless `--import` step, done. A *new*
  filename needs the one `preload("res://assets/textures/...")` line in
  whichever renderer/`Level` updated to point at it.
- **Minimum size, or the fix silently un-fixes itself.** The texture must
  be comfortably larger than the biggest tile drawn from it — 48×48 for
  floor/water, up to 48×32 for the wall's tallest face (its own top
  face). Go smaller and `TileTextureVariant.variant_for()`'s defensive
  clamp forces every tile's crop offset to `(0,0)`, quietly reintroducing
  the "every tile looks identical" bug this system exists to prevent —
  not a crash, not a test failure (this project's renderer tests
  deliberately don't assert on pixels, by established convention — see
  `docs/superpowers/plans/2026-07-20-tile-texture-variation.md`'s Global
  Constraints), just a regression you'd only catch by looking. Bigger
  than the minimum is always safer — more room means more distinct crop
  positions.
- **True seamless-tiling matters less than it used to.** The old 3×3/4×4
  composite check existed for a continuously-*repeated* single texture;
  now every tile takes an independent crop with a hard rectangular edge
  against its neighbor's own independent crop regardless, so adjacent
  tiles were never pixel-continuous with each other in the first place.
  What actually matters: no single strong focal feature (a bright spot, a
  hard edge, one obvious crack/rock/detail) that would look odd cropped
  at an arbitrary offset. Evenly-distributed mottling/speckle — what every
  material generated so far already is — is exactly the safe case.
- **Non-square wall dest rects.** The wall's front face and overdraw band
  are 48×16, not 48×48 — `wall_material.png` needs enough height (≥16px,
  ideally much more for variety) as well as width. This is a sizing note
  only, not a flip caveat: flipping uses a canvas transform
  (`draw_set_transform`, scale `-1`), not a negative-size `Rect2`,
  precisely because the latter was found to silently render as a
  position-shifted gap (reading as solid black) on this project's actual
  runtime — affecting square tiles (floor) exactly as much as non-square
  ones (wall faces). Already fixed in `TileTextureVariant.draw_varied()`;
  mentioned here only so a *new* piece of drawing code elsewhere doesn't
  reach for that same idiom and reintroduce it.

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
`player_wolf_spider.png` (92×92, now Wolf's reference art),
`enemy_trapdoor_spider.png` (92×92, now Warden's reference art — no longer
a separate "enemy" species), `larva.png` (48×48), `web_shot.png` (40×40),
`web_shot_spent.png` (76×76), `web_trap.png` (116×116),
`web_trap_spent.png` (126×126).

**Not yet made** (roughly in priority order for a maze that currently has
no tileset at all):
1. Floor/wall/pit/water tileset (§8) — biggest visible gap, everything else
   renders as flat rectangles right now.
2. Ogre and Echo's own sprites, each with a distinct silhouette per §5 (not
   a recolor of Wolf/Warden's body) — Wolf and Warden already have
   reference art (see above), Ogre and Echo don't yet.
3. Centipede body segment tile.
4. Item icons (Fungus Poison, Fungus Sense, Seed Pod, Lure) — currently
   plain colored dots.
5. Prey variants (Fungal Larva, Beetle, Ant, Cicada Nymph) — currently all
   render as the plain larva.
6. Skill VFX: Warden's barricade, Echo's camouflage outline + decoy effigy,
   Ogre's Net Hold/Shot projectile, Wolf's egg-mine cocoon and
   hatchling/mine-burst spiderlings.
7. Hazard VFX polish: flood water texture, compaction dust, Express
   carve-burst.

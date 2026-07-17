# Burrow — Full Art & Animation Pipeline (Design)

## 1. Goal

Replace *every* visual asset in Burrow — including the 7 sprites that exist
today (`player_wolf_spider.png`, `enemy_trapdoor_spider.png`, `larva.png`,
and the four web assets) — with a new, consistent, fully animated asset set.
The existing sprites are placeholders and are not being kept; nothing is
grandfathered in. This document defines the reusable generation pipeline and
the sequenced backlog of work it will be run against. It does not itself
generate any art — each numbered category below becomes its own
brainstorm → spec → plan → build cycle, the same pattern the project's
original 9-item gameplay roadmap (`docs/superpowers/specs/` history) already
used successfully.

## 2. Non-goals

- Reconsidering anatomy realism, palette, top-down resting pose, or
  color-language rules — `docs/art-bible.md` §§2–3 remain authoritative on
  those. The one style pillar that *did* change is the rendering direction
  itself: §2 was revised 2026-07-17, alongside this tooling change, to a
  retro/indie pixel-art look (driven by SpriteCook cost and the user's
  preference), replacing the prior semi-realistic/soft-edged direction.
  That's a closed decision as of this revision, not an open one for
  Category 0 to re-litigate — Category 0 executes it and becomes the new
  reference anchor.
- Wiring up `PreyType`/prey-variant gameplay logic. `resources/prey_type.gd`
  exists but has zero `.tres` instances and `Larva` never references it —
  that's a code prerequisite for Category 3, tracked there, not solved by
  this pipeline.
- Replacing the Camouflage/Sense reveal techniques. Both are shader-driven
  (`assets/shaders/outline.gdshader`) outlining whatever sprite already
  exists — a technique, not an asset gap. Out of scope.
- Real-dollar cost accounting. SpriteCook doesn't expose real-dollar
  pricing, only credit costs (`list_generation_models`,
  `list_character_workflows`) and live balance (`get_credit_balance`, see
  §4/§9) — this pipeline budgets in credits against the user's monthly
  subscription allowance, not dollars.

## 3. Current state (re-audited 2026-07-17, supersedes art-bible §11)

`docs/art-bible.md` was written 2026-07-14, before the Phase 2 tunnel visual
rework landed (2026-07-17, PR #16). A fresh codebase sweep confirms:

- **Asset files on disk are unchanged**: still exactly the 7 sprites listed
  above, 0 tileset files, 3 utility shaders (none are "art," all are
  effects: outline, ground-dim, ground-blur).
- **Two new placeholder entities appeared since the bible was written** and
  were never inventoried: `Blockade` (`entities/skills/scenes/blockade.gd`,
  drawn rect) and `CentipedeSegment`/`CentipedeExpressRider`
  (`entities/centipede/centipede_segment.gd`, drawn rect).
- **The maze renderer is still 100% procedural** (`world/maze/maze_renderer.gd`,
  `world/maze/floor_renderer.gd`) despite Phase 2 adding real visual
  sophistication (two-tone faux-3D wall blocks, ceiling mirroring, an
  occlusion mask). Zero `TileSet`/`TileMapLayer` resource exists anywhere in
  the repo.
- **Ogre and Echo have no distinct silhouette** — both render
  `player_wolf_spider.png` with a color tint, same as Wolf. Warden-as-player
  has the same problem despite Warden's own reference art
  (`enemy_trapdoor_spider.png`) already existing and being used correctly
  when Warden is rolled as the *enemy*.
- **A real code bug, not just an art gap**: `Enemy` (`entities/enemy/enemy.gd`)
  always renders the trapdoor-spider texture regardless of which class it
  rolls, instead of mirroring `Player`'s per-class texture selection. A
  "Wolf" rival today visually looks like Warden's body tinted orange. This
  needs fixing alongside Category 2's art, since new per-class art is
  pointless if `Enemy` can't select the right texture.
- **Zero animation infrastructure exists anywhere in the codebase.** Every
  entity is either a static `Sprite2D` or a hand-coded `_draw()` placeholder.
  No `AnimatedSprite2D`/`SpriteFrames` usage exists today.

Full per-entity breakdown (creatures, tiles, items, VFX, UI — current state,
file:line) was captured during this design's research pass and is not
duplicated here; see the category sections below for what each covers.

## 4. Tooling

**SpriteCook only.** Comfy Cloud is dropped from this pipeline entirely —
it cost more per asset than SpriteCook for the same work, once SpriteCook's
published credit costs were checked directly (see below), and a
two-platform split added manifest/provenance complexity (§6) for no real
benefit once SpriteCook covers stills, tiles, and animation on its own.
SpriteCook (the same tool that produced the original 7 placeholder
sprites, tracked in `spritecook-assets.json`) was authenticated in a
separate session; this revision re-verified it directly —
`get_credit_balance` and `list_recent_assets` both returned live data,
including that original asset history (Wolf spider, trapdoor spider,
larva, web props, all 40–126px).

Every category now maps to a single SpriteCook tool:
- **Stills** (style anchors, VFX stills, item/UI icons) — `generate_game_art`,
  `pixel=true` (see §2 revision above and §5's style decision).
- **Tiles** — `generate_tileset` (autotile piece-set generation, purpose-built
  for this, unlike anything Comfy Cloud offered).
- **Creature animation** — the guided `generate_character` /
  `generate_character_animations` workflow for full creatures (idle/walk/
  attack/hurt/death), or the freeform `animate_game_art` for one-off VFX
  loops that aren't full characters. Both do native per-motion generation —
  no grid-sheet template, no manual slicing (see §5).

**Cost is now a real, live number, not a dashboard check.** SpriteCook
publishes per-operation credit costs directly via `list_generation_models`
and `list_character_workflows` — confirmed 2026-07-17:
- Still image, pixel mode: 8–12 credits, depending on model (cheapest
  non-deprecated: `gemini-3.1-flash-lite-image`, 8 credits at 1K).
- Guided character animation: 12 credits for the base character, ~20
  credits per animation state (idle/walk/attack/hurt/death), plus a 12-credit
  "prep" step for any pose that isn't the default front-facing view.
- `animate_game_art`'s per-motion cost isn't separately published; treat it
  as comparable to the guided workflow's ~20 credits/state until Category 0
  confirms the real number via `get_credit_balance` deltas.

**Budget:** the user is subscribing at 800 credits/month. §5's directional-
art decision (full idle/walk coverage per facing, for consistency with the
faux-3D wall renderer, §5) raises the per-creature estimate to ~250
credits. Across the full roadmap (§8) — roughly 13 creatures at ~250
credits each, plus tiles and VFX/item stills — lands around **3,500–4,500
credits total**, spanning roughly 5–6 months at 800/month rather than the
prior revision's 2–4. §9's per-category checkpoint exists partly to keep
this honest as real numbers replace the estimate; if Category 0's actual
cost runs higher, the directional-coverage decision itself (not just
per-entity scope) becomes the thing to revisit. Balance was 0 credits as
of 2026-07-17, pre-subscription — resolved once the subscription is
active, tracked as a Category 0 prerequisite, not a blocker on this design.

## 5. Generation technique

Two earlier options are dropped: Comfy Cloud's Nano-Banana grid-sheet
templates (`template_purz_nb2_single_image_sprite_sheet`,
`templates-sprite_sheet` — never verified against Burrow's style, needed a
manual `SplitImageToTileList` slice step, and Comfy is no longer in the
pipeline at all per §4) and the semi-realistic/detailed rendering direction
(§2 revision — pixel mode is now the confirmed style, not an open
question). Video-model partner APIs (Kling, Seedance, Wan) were checked and
ruled out for animation independent of either of those — their guidance
and template set frame them for cinematic/cutscene output, not discrete
clean sprite-pose frames; AnimateDiff-family nodes are built for continuous
motion blur, the opposite of what a crisp game sprite needs.

**Per-creature flow (full characters — Categories 0, 2, 3):**
1. `generate_character(prompt, perspective="topdown")` — a guided pixel-art
   base character.
2. `generate_character_animations(character_id, perspective="topdown",
   animation_ids=["idle","idle_back","idle_right","walk_down","walk_up",
   "walk_right","attack","hurt","death"])` — native per-state generation.
3. `export_godot_character_package(run_id)` for a ready-to-import
   `SpriteFrames`/`AnimatedSprite2D` manifest (`spritecook-use-assets-in-godot`).

**This resolves what was an open question in the prior revision** (whether
Player/Enemy's rotation-based facing — `sprite.rotation = facing.angle()`,
`player.gd:124`/`enemy.gd:589` — could stay as-is for a new walk-cycle
animation). Investigating `world/maze/maze_renderer.gd` (the Phase 2
faux-3D wall rework) settled it: the whole tunnel's "physically standing at
floor level" illusion comes from every wall having a *fixed*, never-rotated
lighter-top-face/darker-front-face convention anchored to world-space edges
— nothing else in this renderer ever rotates. A creature sprite that
rotates 90°/180°/270° to face travel direction would be the one visual
element fighting that convention, worse once the sprite has its own
faux-3D shading to match the walls (its "light source" would visibly
disagree with every wall the instant it faces anything but its authored
direction). So: **no rotation.** `idle`/`walk` (the two states visible
continuously while exploring, where the mismatch would be most exposed)
get real directional art — `idle_right`/`walk_right` mirrored to
left in Godot (`scale.x`), `idle`/`walk_down` (front) and `idle_back`/
`walk_up` (back) generated separately. `attack`/`hurt`/`death` (brief,
one-shot, less exposed) stay a single front-facing pose, mirrored
left/right the same way but not corrected for up-facing — a small,
deliberate cost/consistency tradeoff, not an oversight. Player/Enemy's
`_physics_process`/`_face()` change from setting `.rotation` to selecting
the matching named animation (plus `scale.x` for the mirrored direction) —
a real code change, done as part of Category 0 since nothing else can be
visually verified without it.

This raises the per-creature credit estimate from the prior revision's
~124 to roughly **~250 credits** (12 base + idle/idle_back/idle_right at
20–32 each + walk_down/walk_up/walk_right at 20–32 each + attack/hurt/death
at 20 each, mirroring the free left-facing pairs) — see §4's revised
budget.

**Per-asset flow (VFX, items, icons — Categories 4–6, non-character):**
1. `generate_game_art(prompt, pixel=true)` for the still.
2. For anything needing motion (a burst, a pulse, a short loop — not a
   full animation-state set), `animate_game_art(asset_id, prompt,
   output_format="spritesheet")` for a single native per-motion call. No
   grid template or slicing here either.
3. Import into Godot as `Sprite2D` (static) or `AnimatedSprite2D` +
   `SpriteFrames` (animated loop), per `spritecook-use-assets-in-godot`.

**Tiles (Category 1):** `generate_tileset` — purpose-built autotile
piece-set generation (15-piece top-down sets match the existing
`world/maze/tile_types.gd` classification already in the codebase, per §7).
Tiles stay static — no walk-cycle equivalent for a wall — unless a specific
hazard tile (water) earns a small animated loop, generated the same way as
other VFX loops above.

## 6. Asset manifest

SpriteCook's own asset tooling (`get_credit_balance`, `list_recent_assets`)
tracks assets by ID but not by Burrow-specific role/category or Godot
integration status, so this pipeline still maintains its own lightweight
manifest, same shape/spirit as `spritecook-assets.json`, at
`assets/art-manifest.json`:

```json
{
  "assets": [
    {
      "id": "wolf-idle-anchor",
      "category": 2,
      "role": "player_class_wolf",
      "character_id": "<base character asset_id from generate_character>",
      "run_id": "<generate_character_animations run id, for provenance/regeneration>",
      "still_local": "assets/sprites/wolf/wolf_anchor.png",
      "frames_local": "assets/sprites/wolf/frames/",
      "animations": {
        "idle": "<animation asset_id>",
        "idle_back": "<animation asset_id>",
        "idle_right": "<animation asset_id>",
        "walk_down": "<animation asset_id>",
        "walk_up": "<animation asset_id>",
        "walk_right": "<animation asset_id>",
        "attack": "<animation asset_id>",
        "hurt": "<animation asset_id>",
        "death": "<animation asset_id>"
      },
      "status": "approved"
    }
  ]
}
```

Non-character assets (VFX/items/tiles, §5) use the same manifest with
`character_id`/`run_id` swapped for a plain `asset_id` (from
`generate_game_art` or `generate_tileset`) and, where animated, a single
`animation_asset_id` from `animate_game_art` instead of the `animations`
map.

`status` gates integration: `generated` → `approved` (user has visually
signed off, see §8) → `integrated` (wired into a Godot scene).

## 7. Godot integration pattern

Applies uniformly across every category:

- `Sprite2D` → `AnimatedSprite2D` + a `SpriteFrames` resource with named
  animations, wired to existing gameplay signals (movement direction,
  `CombatFx.flash()`/slash calls, death, skill-cast triggers). No new
  animation *logic* is invented — the pipeline hangs new visuals on
  trigger points that already exist in code.
- Every `_draw()` placeholder (Centipede segment, Blockade, Decoy, Ogre's
  net, Wolf's cocoon/spiderlings, item pickup dots, status badges, hazard
  VFX) gets replaced with a real `Sprite2D`/`AnimatedSprite2D` node and
  generated texture, in its own category below.
- The maze itself needs a real `TileSet`/`TileMapLayer` conversion,
  replacing `MazeRenderer`/`FloorRenderer`'s `draw_rect()` calls — a
  rendering-architecture change scoped to Category 1, using the already-built
  15-shape autotile classification in `world/maze/tile_types.gd` (today used
  only for larva facing) to drive tile selection.

## 8. Category roadmap

Sequenced foundation-first, same shape as the original A–I gameplay
roadmap. Each row becomes its own brainstorm → spec → plan → build cycle;
this document sequences them but does not spec categories 1–6 in detail.

| # | Category | Scope |
|---|---|---|
| **0** | **Pipeline proof-of-concept** | New pixel-art style anchor + one full creature (Wolf) taken through `generate_character` → `generate_character_animations` (directional idle/walk, single-pose attack/hurt/death, §5) → Godot `AnimatedSprite2D`, including the `Player` code change from rotation-based to directional-animation-based facing, verified with a real windowed screenshot (not just automated tests — this project has repeatedly found shader/visual bugs invisible to GUT, see the Sense saga in the playtest roadmap history). Gates every other category — nothing else starts until this loop is proven to actually produce usable, on-style output. |
| 1 | Tileset | Floor/wall/pit/water, ground+ceiling variants, real `TileSet`/`TileMapLayer` conversion of the maze renderer. |
| 2 | Player/enemy spiders | Wolf, Warden (new dedicated player sprite — currently borrows Wolf's body), Ogre, Echo — each a distinct silhouette per art-bible §5, animated. Includes fixing `Enemy`'s per-class texture selection bug (§3). |
| 3 | Prey & Centipede | Larva, the 4 prey variants (Fungal Larva/Beetle/Ant/Cicada Nymph — needs `PreyType` wired into `Larva` first as a code prerequisite), Centipede segment. |
| 4 | Web system + items | Web shot/trap + spent variants (currently the only "real art" category, gets regenerated anyway per §1), Fungus Poison, Fungus Sense, Seed Pod, Lure. |
| 5 | Skill VFX | Blockade, Decoy effigy, Net Hold/Shot, Cocoon Mine, hatchling/mine-burst spiderlings. |
| 6 | Hazard VFX + UI | Water Ingress, Seismic Compaction dust, Centipede Express carve-burst, status-effect icons (5), held-item icon, skill-bar icons. |

## 9. Review & cost gates

- **Visual approval gate**: every generated asset is reviewed by the user
  before integration (manifest `status: approved`), same discipline as the
  Sense/Camouflage saga that found three rounds of real playtest-only bugs
  invisible to automated review.
- **Cost checkpoint**: SpriteCook's `get_credit_balance` gives a real
  number, not a dashboard guess — check it after Category 0 completes
  (base character + 6 directional idle/walk states + 3 single-pose combat
  states) to see actual per-creature cost against the ~250-credit estimate
  in §4, before committing to Categories 1–6. Subscription is 800
  credits/month; §4's rough full-backlog estimate (3,500–4,500 credits)
  already assumes this spans multiple months, but Category 0's real
  numbers should confirm or correct that before treating it as a plan. If
  per-creature cost runs meaningfully higher than estimated, re-scope —
  first by reconsidering §5's directional-coverage decision itself (e.g.
  dropping the back-facing pose, or accepting rotation for a subset of
  lower-visibility creatures), then by trimming animation states per
  entity, before generating the full backlog, not after.
- **Render-verified, not test-verified**: per this project's established
  lesson, integration correctness for anything visual is checked with a
  real windowed Godot run/screenshot, not just GUT tests — automated tests
  have repeatedly missed shader compile failures and visual regressions
  here.

## 10. Success criteria

- Every entity/effect listed in §3's re-audit has real generated art,
  none remaining as a `_draw()` placeholder or flat `Color()` literal.
- Every creature has at minimum idle/move/attack/hurt/death animations
  where the gameplay trigger for that state already exists in code.
- All new art is visually traceable to one consistent style anchor per
  art-bible §§2–3.
- `docs/art-bible.md` is updated to reflect the new reference art (replacing
  its current pointers to the placeholder sprites) once Category 0 lands.

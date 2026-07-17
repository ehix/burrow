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

- Reconsidering the visual style itself. `docs/art-bible.md` §§2–3 (palette,
  anatomy realism, top-down resting pose, color-language rules) remain
  authoritative. This pipeline exists to actually *hit* that style
  consistently, not redefine it.
- Wiring up `PreyType`/prey-variant gameplay logic. `resources/prey_type.gd`
  exists but has zero `.tres` instances and `Larva` never references it —
  that's a code prerequisite for Category 3, tracked there, not solved by
  this pipeline.
- Replacing the Camouflage/Sense reveal techniques. Both are shader-driven
  (`assets/shaders/outline.gdshader`) outlining whatever sprite already
  exists — a technique, not an asset gap. Out of scope.
- Real-dollar cost accounting. No tool available to either platform exposes
  pricing; cost control here means checkpointing against the user's account
  dashboard, not computing a budget in advance.

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

**Comfy Cloud only, for now.** SpriteCook (the tool that produced the
original 7 placeholder sprites, tracked in `spritecook-assets.json`) is
documented and has dedicated Godot-export skills, but the user is not
opting to pay for it. Its MCP server also isn't connected in this
environment. Comfy Cloud is confirmed reachable (production, authenticated)
and is the generation tool this pipeline uses. If SpriteCook becomes
available later, it can be folded in per-category without redesigning the
pipeline — the manifest format below (§6) doesn't assume either tool.

Neither platform exposes real pricing or credit-balance via its tools —
cost tracking is a manual dashboard check, not something this pipeline can
automate (see §9).

## 5. Generation technique

Comfy Cloud has no dedicated pixel-art/sprite-animation category. The
closest fit, found by direct research (not assumed), is two templates built
on Google's Nano Banana image model:

- **`template_purz_nb2_single_image_sprite_sheet`** (Nano Banana 2) — one
  reference image in, animated sprite sheet out. Simpler input.
- **`templates-sprite_sheet`** (Nano Banana Pro) — sprite image + a
  `2x2_grid_image.png`-style grid reference in, idle/attack/walk/jump frames
  out.

Neither has been verified against Burrow's specific style. Video-model
partner APIs (Kling, Seedance, Wan) were checked and ruled out — their
guidance and template set frame them for cinematic/cutscene output, not
discrete clean sprite-pose frames; AnimateDiff-family nodes are built for
continuous motion blur, the opposite of what a crisp game sprite needs.

**Per-creature flow:**
1. Generate a new still-image style anchor via `partner_generate`
   (nano-banana-pro or flux — a head-to-head test on the first asset decides
   which matches the art-bible spec better; this decision doesn't need to
   be made until Category 0).
2. Run the anchor through one of the two sprite-sheet templates above to
   get idle/walk/attack/hurt/death frames.
3. Slice the grid output into individual frames using Comfy's grid-split
   nodes (`SplitImageToTileList` / the `split_image_grid_to_tiles`
   subgraph).
4. Import into Godot as a `SpriteFrames` resource + `AnimatedSprite2D`,
   replacing whatever static `Sprite2D` or `_draw()` placeholder currently
   represents that entity.

Tiles are the one category kept **static** — no walk-cycle equivalent for a
wall — unless a specific hazard tile (water) earns a small animated loop
during Category 1.

## 6. Asset manifest

Since SpriteCook's manifest tooling (`spritecook-assets.json`,
`get_credit_balance`, `list_recent_assets`) isn't in play, this pipeline
maintains its own lightweight manifest, same shape/spirit, at
`assets/art-manifest.json`:

```json
{
  "assets": [
    {
      "id": "wolf-idle-anchor",
      "category": 2,
      "role": "player_class_wolf",
      "model": "vertexai/nano-banana-pro",
      "prompt_id": "<comfy prompt_id, for provenance/regeneration>",
      "still_local": "assets/sprites/wolf/wolf_anchor.png",
      "spritesheet_local": "assets/sprites/wolf/wolf_sheet.png",
      "frames_local": "assets/sprites/wolf/frames/",
      "animations": ["idle", "move", "attack", "hurt", "death"],
      "status": "approved"
    }
  ]
}
```

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
| **0** | **Pipeline proof-of-concept** | New style anchor + one full creature (Wolf) taken through still → sheet → sliced frames → Godot `AnimatedSprite2D`, verified with a real windowed screenshot (not just automated tests — this project has repeatedly found shader/visual bugs invisible to GUT, see the Sense saga in the playtest roadmap history). Gates every other category — nothing else starts until this loop is proven to actually produce usable, on-style output. |
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
- **Cost checkpoint**: run Category 0 first, then check actual Comfy Cloud
  credit consumption on the user's dashboard before committing to
  Categories 1–6. If sprite-sheet generation costs meaningfully more than a
  single still, re-scope (e.g. fewer animation states per entity, or
  static-only for lower-visibility entities) before generating the full
  backlog, not after.
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

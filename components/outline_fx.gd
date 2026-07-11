class_name OutlineFx
extends RefCounted
## Static-only helper (mirrors CombatFx's pattern) for toggling the shared
## outline shader on a sprite — used by Sense (blanket reveal cue) and
## Camouflage (silhouette-while-hidden). Lazily creates and caches a
## ShaderMaterial on the sprite itself on first use, so repeated calls never
## stack a new material.
##
## Reference-counted (final-review fix): Sense's blanket effect and
## Camouflage can both target the same sprite at once — e.g. an enemy is
## camouflaged while caught in the player's Sense pulse, or a Decoy player
## camouflages itself and then eats a Fungus Sense item. Without a count,
## whichever effect ended first would flip the shader fully off even though
## the other caller still wants it on. `enabled=true` means "I want this
## on" and increments a per-sprite counter; `enabled=false` means "I'm done"
## and decrements it (floored at zero, so a stray/unmatched `false` is a
## no-op rather than going negative). The shader's `outline_enabled` uniform
## only actually goes false once every caller has released it. This means
## callers must pair each `true` with exactly one matching `false` — verified
## for both current callers: CamouflageSkill's cooldown (8s) outlives its own
## duration (5s), so `_on_activate()` can't fire again before
## `break_camouflage()` has already run for the prior activation; and
## StatusEffectComponent.apply() only emits `effect_applied` on the
## inactive→active edge (re-applying an already-active "sense" tag just
## refreshes its timer in place), so Level.set_sense_outline(true) can't be
## called twice without an intervening `false`.

const OutlineShader := preload("res://assets/shaders/outline.gdshader")

## Per-sprite "how many callers currently want this on" count, keyed by
## instance ID rather than the sprite itself so this dictionary can never
## keep a freed sprite alive or hold a stale reference to one.
static var _ref_counts: Dictionary = {}


## Toggle the outline effect on `sprite`. No-op if `sprite` is null.
## `enabled=true` increments the caller count for `sprite` (turning the
## outline on, if it wasn't already); `enabled=false` decrements it (turning
## the outline back off only once the count reaches zero). `color` updates
## on every call — last caller's tint wins — since only the on/off state
## needs reference counting, not the color itself.
static func set_outline(sprite: CanvasItem, enabled: bool, color: Color = Color.WHITE) -> void:
	if sprite == null:
		return
	var id := sprite.get_instance_id()
	var count: int = _ref_counts.get(id, 0)
	count = count + 1 if enabled else maxi(0, count - 1)
	if count > 0:
		_ref_counts[id] = count
	else:
		_ref_counts.erase(id)
	var mat := _material_of(sprite)
	mat.set_shader_parameter("outline_enabled", count > 0)
	mat.set_shader_parameter("outline_color", color)


static func _material_of(sprite: CanvasItem) -> ShaderMaterial:
	var mat := sprite.material as ShaderMaterial
	if mat == null or mat.shader != OutlineShader:
		mat = ShaderMaterial.new()
		mat.shader = OutlineShader
		sprite.material = mat
	return mat

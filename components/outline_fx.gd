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
	_release_if_neutral(sprite)


## Sets the shader's body_alpha uniform directly — no ref-counting (unlike
## set_outline()'s on/off toggle, there's only ever one "true" opacity value
## at a time; the last caller wins, same as the old `modulate.a` assignment
## this replaces in CamouflageSkill).
static func set_body_alpha(sprite: CanvasItem, alpha: float) -> void:
	if sprite == null:
		return
	# Nothing to do if there's no material yet and this call wouldn't need
	# one either -- the overwhelmingly common case (an entity that's never
	# left its own plane, never been camouflaged or Sensed) never touches
	# the shader at all.
	if is_equal_approx(alpha, 1.0) and (sprite.material as ShaderMaterial == null or (sprite.material as ShaderMaterial).shader != OutlineShader):
		return
	var mat := _material_of(sprite)
	mat.set_shader_parameter("body_alpha", alpha)
	_release_if_neutral(sprite)


static func _material_of(sprite: CanvasItem) -> ShaderMaterial:
	var mat := sprite.material as ShaderMaterial
	if mat == null or mat.shader != OutlineShader:
		mat = ShaderMaterial.new()
		mat.shader = OutlineShader
		sprite.material = mat
	return mat


## Once neither effect this shader provides is actually doing anything
## (outline off for every caller AND body_alpha back to its neutral 1.0),
## detaches the material entirely and restores `sprite.material` to null --
## every sprite this project ever applies the outline shader to starts with
## no material of its own. Leaving a "neutral" ShaderMaterial permanently
## attached instead (found via playtest: a ceiling-plane transition dims
## the off-plane spider via set_body_alpha(), and the shader visibly never
## came back off even once alpha returned to 1.0) takes the sprite out of
## the engine's default per-item rendering path for good, for no reason --
## the numeric effect is already fully neutral, so there's nothing left for
## a lingering material to be doing.
static func _release_if_neutral(sprite: CanvasItem) -> void:
	var mat := sprite.material as ShaderMaterial
	if mat == null or mat.shader != OutlineShader:
		return
	var id := sprite.get_instance_id()
	var outline_active: bool = _ref_counts.get(id, 0) > 0
	# get_shader_parameter() returns null (not the shader's own declared
	# default) for a uniform this material has never explicitly set --
	# an unset body_alpha is still the neutral 1.0, just not overridden yet.
	var alpha_param: Variant = mat.get_shader_parameter("body_alpha")
	var alpha: float = alpha_param if alpha_param != null else 1.0
	if not outline_active and is_equal_approx(alpha, 1.0):
		sprite.material = null

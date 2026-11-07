extends Control
## One visualizer layer. Hosts a renderer (see RENDERERS) that reads the shared audio
## service and draws with custom canvas drawing. Several layers are stacked by the
## Director: atmosphere, secondary, main and the beat-light overlay.

const Common := preload("res://vis/common.gd")
const RENDERERS := {
	"waveform": preload("res://vis/classic.gd"),
	"grid": preload("res://vis/classic.gd"),
	"seven_waves": preload("res://vis/classic.gd"),
	"retro": preload("res://vis/classic.gd"),
	"orbs": preload("res://vis/classic.gd"),
	"aurora": preload("res://vis/aurora.gd"),
	"particles": preload("res://vis/particles.gd"),
	"resonance": preload("res://vis/resonance.gd"),
	"spirits": preload("res://vis/spirits.gd"),
	"glow": preload("res://vis/atmosphere.gd"),
	"dust": preload("res://vis/atmosphere.gd"),
	"beatlight": preload("res://vis/atmosphere.gd"),
}
## Display names for the Studio, in menu order.
const MODE_NAMES := {
	"waveform": "Waveform", "grid": "Square Grid", "seven_waves": "Seven Waves", "retro": "Retro Spectrum",
	"orbs": "Glowing Orbs", "aurora": "The Aurora", "particles": "Particle Universe",
	"resonance": "Resonance Engine", "spirits": "The Seven Spirits",
}
const ATMOSPHERE_NAMES := {"none": "None", "glow": "Ambient Glow", "dust": "Drifting Dust"}

var audio: Node
var mode := "none"
var renderer: RefCounted
var opacity := 1.0
var scale_factor := 1.0
var intensity := 1.0
var speed := 1.0
var glow := 1.0
var trail := 0.5
var density := 1.0  # Particle-count multiplier (song personality / per-song setting).
var primary := Color(1.0, 0.82, 0.45)
var secondary := Color(0.80, 0.50, 0.32)
var custom_color := false  # Song chose a colour: classic modes use its derived palette.
var additive_material := CanvasItemMaterial.new()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


func set_mode(new_mode: String) -> void:
	if new_mode == mode and renderer != null:
		return
	mode = new_mode
	renderer = null
	if RENDERERS.has(mode):
		renderer = RENDERERS[mode].new(self, mode)
	visible = renderer != null
	queue_redraw()


func set_blend(additive: bool) -> void:
	material = additive_material if additive else null


func _process(delta: float) -> void:
	if renderer == null or audio == null:
		return
	modulate.a = opacity
	if opacity <= 0.01:
		return
	renderer.update(minf(delta, 0.05) * speed)
	queue_redraw()


func _draw() -> void:
	if renderer == null or audio == null or opacity <= 0.01:
		return
	if not is_equal_approx(scale_factor, 1.0):
		var c := size * 0.5
		draw_set_transform(c * (1.0 - scale_factor), 0.0, Vector2(scale_factor, scale_factor))
	renderer.draw()


## Number of live particles/entities, for the diagnostics overlay.
func element_count() -> int:
	return renderer.element_count() if renderer and renderer.has_method("element_count") else 0

extends Control
## One visualizer layer. Hosts a renderer (see RENDERERS) that reads the shared audio
## service and draws with custom canvas drawing (or a shader). Several layers are stacked
## by the Director: atmosphere, secondary, main and the beat-light overlay.

const Common := preload("res://vis/common.gd")
const RENDERERS := {
	"waveform": preload("res://vis/waveform.gd"),
	"grid": preload("res://vis/grid.gd"),
	"retro": preload("res://vis/retro.gd"),
	"aurora": preload("res://vis/aurora.gd"),
	"particles": preload("res://vis/particles.gd"),
	"resonance": preload("res://vis/resonance.gd"),
	"spirits": preload("res://vis/spirits.gd"),
	"ribbons": preload("res://vis/ribbons.gd"),
	"pulse_rings": preload("res://vis/pulse_rings.gd"),
	"northern_lights": preload("res://vis/northern_lights.gd"),
	"glow": preload("res://vis/atmosphere.gd"),
	"dust": preload("res://vis/atmosphere.gd"),
	"beatlight": preload("res://vis/atmosphere.gd"),
}
## Display names for the Studio, in menu order.
const MODE_NAMES := {
	"waveform": "Multi-Waveform", "grid": "Square Grid", "retro": "Retro Spectrum",
	"aurora": "The Aurora", "particles": "Particle Universe", "resonance": "Resonance Engine",
	"spirits": "The Seven Spirits", "ribbons": "Harmonic Ribbons", "pulse_rings": "Pulse Rings",
	"northern_lights": "Northern Lights",
}
const ATMOSPHERE_NAMES := {"none": "None", "glow": "Ambient Glow", "dust": "Drifting Dust"}
## Visualizer-specific settings shown in the Studio: key -> [label, min, max, step].
const MODE_PARAMS := {
	"waveform": {"count": ["Lines", 1, 7, 1], "thickness": ["Line thickness", 0.3, 3.0, 0.05], "range": ["Movement", 0.0, 2.0, 0.01]},
	"grid": {"density": ["Grid density", 0.5, 2.0, 0.05], "size": ["Square size", 0.3, 1.0, 0.01], "range": ["Movement", 0.0, 2.0, 0.01]},
	"retro": {"density": ["Columns", 0.5, 2.0, 0.05], "size": ["Block size", 0.4, 1.0, 0.01], "trail": ["Peak hold", 0.0, 1.0, 0.01]},
	"aurora": {"range": ["Movement", 0.0, 2.0, 0.01]},
	"particles": {"density": ["Density", 0.3, 2.0, 0.05], "size": ["Particle size", 0.5, 2.0, 0.05], "depth": ["Depth", 0.3, 2.0, 0.05], "range": ["Movement", 0.0, 2.0, 0.01], "trail": ["Trails", 0.0, 1.0, 0.01]},
	"resonance": {"range": ["Distortion", 0.0, 2.0, 0.01]},
	"spirits": {"size": ["Spirit size", 0.4, 2.0, 0.05], "range": ["Movement range", 0.2, 2.0, 0.01], "response": ["Responsiveness", 0.0, 2.0, 0.01], "spacing": ["Spacing", 0.4, 1.8, 0.01], "trail": ["Trails", 0.0, 1.0, 0.01]},
	"ribbons": {"count": ["Ribbons", 1, 7, 1], "thickness": ["Ribbon width", 0.3, 2.5, 0.05], "range": ["Movement", 0.0, 2.0, 0.01]},
	"pulse_rings": {"count": ["Rings", 2, 9, 1], "thickness": ["Thickness", 0.3, 3.0, 0.05], "response": ["Responsiveness", 0.0, 2.0, 0.01]},
	"northern_lights": {"count": ["Curtains", 1, 4, 1], "range": ["Movement", 0.0, 2.0, 0.01]},
}

var audio: Node
var mode := "none"
var renderer: RefCounted
var cfg := {}  # This layer's preset settings (see presets.gd LAYER_DEFAULT).
var opacity := 1.0
var scale_factor := 1.0
var intensity := 1.0
var speed := 1.0
var glow := 1.0
var trail := 0.5
var density := 1.0  # Particle-count multiplier (song personality / per-song setting).
var primary := Color(1.0, 0.82, 0.45)
var secondary := Color(0.80, 0.50, 0.32)
var palette: Array = Common.BAND_COLORS.duplicate()  # 7 element colours.
var additive_material := CanvasItemMaterial.new()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


func set_mode(new_mode: String) -> void:
	if new_mode == mode and renderer != null:
		return
	if renderer and renderer.has_method("dispose"):
		renderer.dispose()
	mode = new_mode
	renderer = null
	if RENDERERS.has(mode):
		renderer = RENDERERS[mode].new(self, mode)
	visible = renderer != null
	queue_redraw()


func set_blend(additive: bool) -> void:
	material = additive_material if additive else null


## A visualizer-specific setting from this layer's preset.
func p(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


func color(i: int) -> Color:
	return palette[posmod(i, palette.size())] if not palette.is_empty() else primary


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


## Lights this layer casts on the dancing companion: [position (screen), colour with
## alpha = intensity]. Renderers can report their own (spirits, aurora, ...); otherwise the
## palette colours are placed across the screen from bass (left) to treble (right) at the
## actual band energies. Scaled by this layer's opacity and glow.
func light_sources() -> Array:
	if renderer == null or opacity <= 0.01:
		return []
	var out: Array = []
	if renderer.has_method("light_sources"):
		out = renderer.light_sources()
	else:
		for i in 7:
			out.append([Vector2(size.x * (i + 0.5) / 7.0, size.y * 0.5), Color(color(i), float(audio.bands7[i]) * 0.9)])
	var k := opacity * clampf(glow, 0.0, 1.5)
	for l in out:
		l[1].a *= k
	return out


## Number of live particles/entities, for the diagnostics overlay.
func element_count() -> int:
	return renderer.element_count() if renderer and renderer.has_method("element_count") else 0

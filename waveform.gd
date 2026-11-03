extends Control

const POINTS := 160
const MIN_HZ := 40.0
const MAX_HZ := 8000.0
const COPPER := Color(0.80, 0.50, 0.32)
const AMBER := Color(1.0, 0.68, 0.32)
const GOLD := Color(1.0, 0.82, 0.45)

enum Mode { WAVEFORM, GRID }

var mode := Mode.WAVEFORM
## 1.0 is the original look; set from the Intensity slider (0–100% maps to 0–2).
var intensity_scale := 1.0
## How easily the visuals react to audio; 1.0 is the original response (0–200% slider).
var sensitivity := 1.0
## 0 keeps the base colour; 1 allows the full palette range.
var hue_sensitivity := 0.5
var palette := [COPPER, AMBER, GOLD]

var analyzer_index := 0
var levels := PackedFloat32Array()
var band := PackedInt32Array()  # 0 = low, 1 = vocal range, 2 = high
var intensity := 0.0
var vocal_avg := 0.33
var tone := 1.0
var t := 0.0


func _ready() -> void:
	AudioServer.add_bus_effect(0, AudioEffectSpectrumAnalyzer.new())
	analyzer_index = AudioServer.get_bus_effect_count(0) - 1
	levels.resize(POINTS)
	band.resize(POINTS)
	for i in POINTS:
		var hz := MIN_HZ * pow(MAX_HZ / MIN_HZ, float(i) / POINTS)
		band[i] = 0 if hz < 250.0 else (1 if hz < 3000.0 else 2)


## Default (non-custom) keeps the original gold/amber/copper palette; a custom colour
## gets a matching warmer, darker range so hue variation stays subtle around it.
func set_base_color(c: Color, custom: bool) -> void:
	if not custom:
		palette = [COPPER, AMBER, GOLD]
		return
	palette = [
		Color.from_hsv(wrapf(c.h - 0.06, 0.0, 1.0), minf(c.s * 1.1, 1.0), c.v * 0.78),
		Color.from_hsv(wrapf(c.h - 0.03, 0.0, 1.0), c.s, c.v * 0.9),
		c,
	]


func _process(delta: float) -> void:
	t += delta
	# Fetched each frame: adding other bus effects (the EQ) recreates effect instances.
	var spectrum := AudioServer.get_bus_effect_instance(0, analyzer_index) as AudioEffectSpectrumAnalyzerInstance
	var sums := [0.0, 0.0, 0.0]
	for i in POINTS:
		var a := MIN_HZ * pow(MAX_HZ / MIN_HZ, float(i) / POINTS)
		var b := MIN_HZ * pow(MAX_HZ / MIN_HZ, float(i + 1) / POINTS)
		var db := linear_to_db(spectrum.get_magnitude_for_frequency_range(a, b).length())
		var v := clampf((db + 70.0) / 60.0 * sensitivity, 0.0, 1.0)
		levels[i] = lerpf(levels[i], v, 1.0 - exp(-delta * 4.0))
		sums[band[i]] += levels[i]
	var total: float = sums[0] + sums[1] + sums[2]
	intensity = lerpf(intensity, total / POINTS, 1.0 - exp(-delta * 2.0))

	# Hue drifts toward the base colour when the vocal range rises above its recent
	# average, and toward the warmer/darker tones when other instruments dominate.
	if total > 1.0:
		var vocal_share: float = sums[1] / total
		vocal_avg = lerpf(vocal_avg, vocal_share, 1.0 - exp(-delta * 0.15))
		var target := 1.0 - hue_sensitivity * clampf(0.5 - (vocal_share - vocal_avg) * 6.0, 0.0, 1.0)
		tone = lerpf(tone, target, 1.0 - exp(-delta * 1.0))
	queue_redraw()


func _tone_color(x: float) -> Color:
	return palette[0].lerp(palette[1], x * 2.0) if x < 0.5 else palette[1].lerp(palette[2], x * 2.0 - 1.0)


func _draw() -> void:
	if mode == Mode.GRID:
		_draw_grid()
	else:
		_draw_waveform()


func _draw_waveform() -> void:
	var w := size.x
	var cy := size.y * 0.5
	var amp := size.y * 0.06 * intensity_scale
	var line := PackedVector2Array()
	line.resize(POINTS)
	for i in POINTS:
		var p := float(i) / (POINTS - 1)
		# Light spatial smoothing across neighbouring bands.
		var l := (levels[max(i - 1, 0)] + 2.0 * levels[i] + levels[min(i + 1, POINTS - 1)]) * 0.25
		var envelope := sin(p * PI)
		var y := sin(p * TAU * 3.0 + t * 0.8) * l * amp * envelope
		line[i] = Vector2(p * w, cy + y)

	var col := _tone_color(tone)
	var glow := (0.06 + intensity * 0.25) * intensity_scale
	draw_polyline(line, Color(col, glow * 0.35), 14.0, true)
	draw_polyline(line, Color(col, glow * 0.6), 7.0, true)
	draw_polyline(line, Color(col, glow), 3.5, true)
	draw_polyline(line, Color(col.lightened(0.35), 0.95), 1.5, true)


## Columns map left→right from low to high frequencies; squares swell toward the
## centre rows with band energy and overall volume.
func _draw_grid() -> void:
	var area := Rect2(size * Vector2(0.15, 0.32), size * Vector2(0.7, 0.36))
	var spacing := clampf(area.size.y / 8.0, 14.0, 40.0)
	var cols := int(area.size.x / spacing)
	var rows := int(area.size.y / spacing)
	var origin := area.get_center() - Vector2(cols - 1, rows - 1) * spacing * 0.5
	for c in cols:
		var p := (c + 0.5) / cols
		var e := levels[int(p * (POINTS - 1))]
		var col := _tone_color(clampf(tone - (1.0 - p) * 0.25 * hue_sensitivity, 0.0, 1.0))
		for r in rows:
			var dist := absf(r - (rows - 1) * 0.5) / maxf(rows * 0.5, 1.0)
			var wobble := 0.88 + 0.12 * sin(t * 0.6 + c * 1.3 + r * 2.1)
			var k := clampf((e * 1.3 + intensity * 0.4 - dist * 0.7) * wobble, 0.0, 1.0) * intensity_scale
			var s := spacing * clampf(0.12 + 0.5 * k, 0.12, 0.8)
			var center := origin + Vector2(c, r) * spacing
			draw_rect(Rect2(center - Vector2(s, s), Vector2(s, s) * 2.0), Color(col, 0.07 * k))
			draw_rect(Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s)), Color(col.lightened(0.2), 0.3 + 0.5 * minf(k, 1.0)))

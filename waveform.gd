extends Control

const POINTS := 160
const MIN_HZ := 40.0
const MAX_HZ := 8000.0
const COPPER := Color(0.80, 0.50, 0.32)
const AMBER := Color(1.0, 0.68, 0.32)
const GOLD := Color(1.0, 0.82, 0.45)

## 1.0 is the original look; set from the Intensity slider (0–100% maps to 0–2).
var intensity_scale := 1.0
## 0 keeps pure gold; 1 allows the full gold–amber–copper range.
var hue_sensitivity := 0.5

var spectrum: AudioEffectSpectrumAnalyzerInstance
var levels := PackedFloat32Array()
var band := PackedInt32Array()  # 0 = low, 1 = vocal range, 2 = high
var intensity := 0.0
var vocal_avg := 0.33
var tone := 1.0
var t := 0.0


func _ready() -> void:
	AudioServer.add_bus_effect(0, AudioEffectSpectrumAnalyzer.new())
	spectrum = AudioServer.get_bus_effect_instance(0, AudioServer.get_bus_effect_count(0) - 1)
	levels.resize(POINTS)
	band.resize(POINTS)
	for i in POINTS:
		var hz := MIN_HZ * pow(MAX_HZ / MIN_HZ, float(i) / POINTS)
		band[i] = 0 if hz < 250.0 else (1 if hz < 3000.0 else 2)


func _process(delta: float) -> void:
	t += delta
	var sums := [0.0, 0.0, 0.0]
	for i in POINTS:
		var a := MIN_HZ * pow(MAX_HZ / MIN_HZ, float(i) / POINTS)
		var b := MIN_HZ * pow(MAX_HZ / MIN_HZ, float(i + 1) / POINTS)
		var db := linear_to_db(spectrum.get_magnitude_for_frequency_range(a, b).length())
		var v := clampf((db + 70.0) / 60.0, 0.0, 1.0)
		levels[i] = lerpf(levels[i], v, 1.0 - exp(-delta * 4.0))
		sums[band[i]] += levels[i]
	var total: float = sums[0] + sums[1] + sums[2]
	intensity = lerpf(intensity, total / POINTS, 1.0 - exp(-delta * 2.0))

	# Hue drifts toward gold when the vocal range rises above its recent average,
	# and toward amber/copper when lower or higher instruments dominate.
	if total > 1.0:
		var vocal_share: float = sums[1] / total
		vocal_avg = lerpf(vocal_avg, vocal_share, 1.0 - exp(-delta * 0.15))
		var target := 1.0 - hue_sensitivity * clampf(0.5 - (vocal_share - vocal_avg) * 6.0, 0.0, 1.0)
		tone = lerpf(tone, target, 1.0 - exp(-delta * 1.0))
	queue_redraw()


func _draw() -> void:
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

	var col: Color = COPPER.lerp(AMBER, tone * 2.0) if tone < 0.5 else AMBER.lerp(GOLD, tone * 2.0 - 1.0)
	var glow := (0.06 + intensity * 0.25) * intensity_scale
	draw_polyline(line, Color(col, glow * 0.35), 14.0, true)
	draw_polyline(line, Color(col, glow * 0.6), 7.0, true)
	draw_polyline(line, Color(col, glow), 3.5, true)
	draw_polyline(line, Color(col.lightened(0.35), 0.95), 1.5, true)

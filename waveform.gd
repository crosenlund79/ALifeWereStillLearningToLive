extends Control

const POINTS := 160
const MIN_HZ := 40.0
const MAX_HZ := 8000.0
const GOLD := Color(1.0, 0.82, 0.45)

var spectrum: AudioEffectSpectrumAnalyzerInstance
var levels := PackedFloat32Array()
var intensity := 0.0
var t := 0.0


func _ready() -> void:
	AudioServer.add_bus_effect(0, AudioEffectSpectrumAnalyzer.new())
	spectrum = AudioServer.get_bus_effect_instance(0, AudioServer.get_bus_effect_count(0) - 1)
	levels.resize(POINTS)


func _process(delta: float) -> void:
	t += delta
	var total := 0.0
	for i in POINTS:
		var a := MIN_HZ * pow(MAX_HZ / MIN_HZ, float(i) / POINTS)
		var b := MIN_HZ * pow(MAX_HZ / MIN_HZ, float(i + 1) / POINTS)
		var db := linear_to_db(spectrum.get_magnitude_for_frequency_range(a, b).length())
		var v := clampf((db + 70.0) / 60.0, 0.0, 1.0)
		levels[i] = lerpf(levels[i], v, 1.0 - exp(-delta * 4.0))
		total += levels[i]
	intensity = lerpf(intensity, total / POINTS, 1.0 - exp(-delta * 2.0))
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var cy := size.y * 0.5
	var amp := size.y * 0.06
	var line := PackedVector2Array()
	line.resize(POINTS)
	for i in POINTS:
		var p := float(i) / (POINTS - 1)
		# Light spatial smoothing across neighbouring bands.
		var l := (levels[max(i - 1, 0)] + 2.0 * levels[i] + levels[min(i + 1, POINTS - 1)]) * 0.25
		var envelope := sin(p * PI)
		var y := sin(p * TAU * 3.0 + t * 0.8) * l * amp * envelope
		line[i] = Vector2(p * w, cy + y)

	var glow := 0.06 + intensity * 0.25
	draw_polyline(line, Color(GOLD, glow * 0.35), 14.0, true)
	draw_polyline(line, Color(GOLD, glow * 0.6), 7.0, true)
	draw_polyline(line, Color(GOLD, glow), 3.5, true)
	draw_polyline(line, Color(1.0, 0.9, 0.65, 0.95), 1.5, true)

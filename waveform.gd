extends Control

const POINTS := 160
const MIN_HZ := 40.0
const MAX_HZ := 8000.0
const COPPER := Color(0.80, 0.50, 0.32)
const AMBER := Color(1.0, 0.68, 0.32)
const GOLD := Color(1.0, 0.82, 0.45)
const EQ_HZ := [60.0, 150.0, 400.0, 1000.0, 2400.0, 6000.0, 15000.0]
const BAND_COLORS := [
	Color(1.0, 0.80, 0.40), Color(1.0, 0.60, 0.32), Color(0.96, 0.46, 0.52), Color(0.78, 0.52, 0.96),
	Color(0.46, 0.64, 1.0), Color(0.36, 0.86, 0.86), Color(0.56, 0.95, 0.60),
]
const RETRO_COLS := 28
const RETRO_ROWS := 16

enum Mode { WAVEFORM, GRID, SEVEN_WAVES, RETRO, ORBS }

var mode := Mode.WAVEFORM
## 1.0 is the original look; set from the Intensity slider (0–100% maps to 0–2).
var intensity_scale := 1.0
## How easily the visuals react to audio; 1.0 is the default response (0–200% slider).
var sensitivity := 1.0
## Fixed amount of audio-reactive hue drift around the base colour.
var hue_sensitivity := 0.5
var palette := [COPPER, AMBER, GOLD]

var analyzer_index := 0
var levels := PackedFloat32Array()
var band := PackedInt32Array()  # 0 = low, 1 = vocal range, 2 = high
var bands7 := PackedFloat32Array()  # Smoothed energy around each EQ band centre.
var band_peaks := PackedFloat32Array()  # Per-band running peak for normalisation.
var agc := 0.5  # Running peak of the spectrum; quiet passages are scaled up toward it.
var intensity := 0.0
var vocal_avg := 0.33
var tone := 1.0
var t := 0.0
var retro_height := PackedFloat32Array()
var retro_peak := PackedFloat32Array()
var retro_hold := PackedFloat32Array()


func _ready() -> void:
	AudioServer.add_bus_effect(0, AudioEffectSpectrumAnalyzer.new())
	analyzer_index = AudioServer.get_bus_effect_count(0) - 1
	levels.resize(POINTS)
	band.resize(POINTS)
	for i in POINTS:
		var hz := MIN_HZ * pow(MAX_HZ / MIN_HZ, float(i) / POINTS)
		band[i] = 0 if hz < 250.0 else (1 if hz < 3000.0 else 2)
	bands7.resize(7)
	band_peaks.resize(7)
	band_peaks.fill(0.5)
	retro_height.resize(RETRO_COLS)
	retro_peak.resize(RETRO_COLS)
	retro_hold.resize(RETRO_COLS)


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


## Fast attack, slower release: reacts promptly without flicker.
func _smooth(current: float, target: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-delta * (14.0 if target > current else 5.0)))


func _db_level(spectrum: AudioEffectSpectrumAnalyzerInstance, a: float, b: float) -> float:
	return clampf((linear_to_db(spectrum.get_magnitude_for_frequency_range(a, b).length()) + 78.0) / 66.0, 0.0, 1.0)


func _process(delta: float) -> void:
	t += delta
	# Fetched each frame: adding other bus effects (the EQ) recreates effect instances.
	var spectrum := AudioServer.get_bus_effect_instance(0, analyzer_index) as AudioEffectSpectrumAnalyzerInstance

	# Automatic gain: follow the loudest recent level up quickly and down over ~6 s,
	# so quiet passages are lifted while loud ones are not pushed into saturation.
	var raw := PackedFloat32Array()
	raw.resize(POINTS)
	var frame_peak := 0.0
	for i in POINTS:
		var a := MIN_HZ * pow(MAX_HZ / MIN_HZ, float(i) / POINTS)
		var b := MIN_HZ * pow(MAX_HZ / MIN_HZ, float(i + 1) / POINTS)
		raw[i] = _db_level(spectrum, a, b)
		frame_peak = maxf(frame_peak, raw[i])
	agc = maxf(frame_peak, agc - delta * 0.08)
	var gain := 0.9 / maxf(agc, 0.35) * sensitivity

	var sums := [0.0, 0.0, 0.0]
	for i in POINTS:
		levels[i] = _smooth(levels[i], clampf(raw[i] * gain, 0.0, 1.0), delta)
		sums[band[i]] += levels[i]
	for i in 7:
		var hz: float = EQ_HZ[i]
		var v := _db_level(spectrum, hz / 1.5, hz * 1.5)
		band_peaks[i] = maxf(v, band_peaks[i] - delta * 0.08)
		bands7[i] = _smooth(bands7[i], clampf(pow(v / maxf(band_peaks[i], 0.35), 1.6) * sensitivity, 0.0, 1.0), delta)
	var total: float = sums[0] + sums[1] + sums[2]
	intensity = lerpf(intensity, total / POINTS, 1.0 - exp(-delta * 3.0))

	# Hue drifts toward the base colour when the vocal range rises above its recent
	# average, and toward the warmer/darker tones when other instruments dominate.
	if total > 1.0:
		var vocal_share: float = sums[1] / total
		vocal_avg = lerpf(vocal_avg, vocal_share, 1.0 - exp(-delta * 0.15))
		var target := 1.0 - hue_sensitivity * clampf(0.5 - (vocal_share - vocal_avg) * 6.0, 0.0, 1.0)
		tone = lerpf(tone, target, 1.0 - exp(-delta * 1.0))

	if mode == Mode.RETRO:
		_update_retro(delta)
	queue_redraw()


func _tone_color(x: float) -> Color:
	return palette[0].lerp(palette[1], x * 2.0) if x < 0.5 else palette[1].lerp(palette[2], x * 2.0 - 1.0)


func _draw() -> void:
	match mode:
		Mode.GRID: _draw_grid()
		Mode.SEVEN_WAVES: _draw_seven_waves()
		Mode.RETRO: _draw_retro()
		Mode.ORBS: _draw_orbs()
		_: _draw_waveform()


func _draw_waveform() -> void:
	var w := size.x
	var cy := size.y * 0.5
	var amp := size.y * 0.08 * intensity_scale
	var line := PackedVector2Array()
	line.resize(POINTS)
	for i in POINTS:
		var p := float(i) / (POINTS - 1)
		# Light spatial smoothing across neighbouring bands.
		var l := (levels[max(i - 1, 0)] + 2.0 * levels[i] + levels[min(i + 1, POINTS - 1)]) * 0.25
		var envelope := sin(p * PI)
		var y := sin(p * TAU * 3.0 + t * 1.0) * l * amp * envelope
		line[i] = Vector2(p * w, cy + y)

	var col := _tone_color(tone)
	var glow := (0.06 + intensity * 0.3) * intensity_scale
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


## Seven stacked lines, one per EQ band (low at the top), each moving with its band's energy.
func _draw_seven_waves() -> void:
	var spacing := size.y * 0.6 / 7.0
	var points := 110
	for i in 7:
		var e := bands7[i]
		var base_y := size.y * 0.2 + spacing * (i + 0.5)
		var amp := spacing * (0.06 + 0.5 * e) * intensity_scale
		var line := PackedVector2Array()
		line.resize(points)
		for j in points:
			var p := float(j) / (points - 1)
			var wave := sin(p * TAU * (1.5 + i * 0.35) + t * (0.9 + i * 0.15)) * 0.75 + sin(p * TAU * 4.1 - t * 1.3 + i) * 0.25
			line[j] = Vector2(p * size.x, base_y + wave * amp * sin(p * PI))
		var col: Color = BAND_COLORS[i]
		var glow := (0.08 + 0.25 * e) * intensity_scale
		draw_polyline(line, Color(col, glow * 0.4), 10.0, true)
		draw_polyline(line, Color(col, glow), 4.0, true)
		draw_polyline(line, Color(col.lightened(0.3), 0.9), 1.5, true)


func _update_retro(delta: float) -> void:
	var per := POINTS / RETRO_COLS
	for c in RETRO_COLS:
		var target := 0.0
		for i in range(c * per, (c + 1) * per):
			target = maxf(target, levels[i])
		target = clampf(target * intensity_scale, 0.0, 1.0)
		# Rise immediately, fall with a steady decay.
		retro_height[c] = maxf(target, retro_height[c] - delta * 1.4)
		if retro_height[c] >= retro_peak[c]:
			retro_peak[c] = retro_height[c]
			retro_hold[c] = 0.6
		elif retro_hold[c] > 0.0:
			retro_hold[c] -= delta
		else:
			retro_peak[c] = maxf(retro_peak[c] - delta * 0.7, retro_height[c])


## Classic block spectrum: green low, yellow middle, orange/red peaks, dim unlit blocks.
func _draw_retro() -> void:
	var area := Rect2(size * Vector2(0.12, 0.22), size * Vector2(0.76, 0.56))
	var cell := minf(area.size.x / RETRO_COLS, area.size.y / RETRO_ROWS)
	var block := cell * 0.8
	var origin := area.get_center() - Vector2(RETRO_COLS, RETRO_ROWS) * cell * 0.5
	for c in RETRO_COLS:
		var lit := int(round(retro_height[c] * RETRO_ROWS))
		var peak_row := mini(int(round(retro_peak[c] * RETRO_ROWS)) - 1, RETRO_ROWS - 1)
		for r in RETRO_ROWS:
			var f := float(r) / (RETRO_ROWS - 1)
			var col := Color(0.25, 0.9, 0.32)
			if f > 0.88:
				col = Color(1.0, 0.24, 0.16)
			elif f > 0.72:
				col = Color(1.0, 0.55, 0.12)
			elif f > 0.5:
				col = Color(1.0, 0.86, 0.22)
			var pos := origin + Vector2(c * cell, (RETRO_ROWS - 1 - r) * cell)
			var rect := Rect2(pos, Vector2(block, block))
			if r < lit or r == peak_row:
				draw_rect(rect.grow(block * 0.15), Color(col, 0.12))
				draw_rect(rect, Color(col, 0.95))
			else:
				draw_rect(rect, Color(0.1, 0.12, 0.1, 0.5))


## Seven soft orbs, one per EQ band, rising and glowing with their band's energy.
func _draw_orbs() -> void:
	var scale_factor := size.y / 941.0
	for i in 7:
		var e := bands7[i]
		var drift := Vector2(sin(t * 0.43 + i * 1.9) * 10.0, sin(t * 0.61 + i * 1.3) * 14.0) * scale_factor
		var pos := Vector2(size.x * (i + 0.5) / 7.0, size.y * 0.55 - e * size.y * 0.18 * intensity_scale) + drift
		var r := (14.0 + e * 22.0 * intensity_scale) * scale_factor
		var col: Color = BAND_COLORS[i]
		for k in range(12, 0, -1):  # Many faint layers give a soft, band-free glow.
			draw_circle(pos, r * (1.0 + k * 0.22), Color(col, (0.025 + 0.05 * e) * intensity_scale * (1.0 - k / 13.0)))
		draw_circle(pos, r, Color(col, 0.55 + 0.35 * e))
		draw_circle(pos, r * 0.5, Color(col.lightened(0.55), 0.85))

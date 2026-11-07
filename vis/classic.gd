extends RefCounted
## The original TinserBox visualizers (Waveform, Square Grid, Seven Waves, Retro
## Spectrum, Glowing Orbs), now driven by the shared audio service.

const Common := preload("res://vis/common.gd")
const RETRO_COLS := 28
const RETRO_ROWS := 16

var L: Control  # The layer we draw on.
var A: Node  # Shared audio service.
var mode: String
var t := 0.0
var line := PackedVector2Array()
var retro_height := PackedFloat32Array()
var retro_peak := PackedFloat32Array()
var retro_hold := PackedFloat32Array()


func _init(layer: Control, m: String) -> void:
	L = layer
	A = layer.audio
	mode = m
	retro_height.resize(RETRO_COLS)
	retro_peak.resize(RETRO_COLS)
	retro_hold.resize(RETRO_COLS)


func update(delta: float) -> void:
	t += delta
	if mode == "retro":
		_update_retro(delta)


## Palette from the layer's colours: [darker/warmer, middle, base], hue drifting with A.tone.
func _tone_color(x: float) -> Color:
	var base: Color = L.primary
	var low: Color = L.secondary
	var middle := low.lerp(base, 0.55)
	return low.lerp(middle, x * 2.0) if x < 0.5 else middle.lerp(base, x * 2.0 - 1.0)


func draw() -> void:
	match mode:
		"grid": _draw_grid()
		"seven_waves": _draw_seven_waves()
		"retro": _draw_retro()
		"orbs": _draw_orbs()
		_: _draw_waveform()


func _draw_waveform() -> void:
	var levels: PackedFloat32Array = A.levels
	var n := levels.size()
	if line.size() != n:
		line.resize(n)
	var w := L.size.x
	var cy := L.size.y * 0.5
	var amp: float = L.size.y * 0.08 * L.intensity
	for i in n:
		var p := float(i) / (n - 1)
		var l := (levels[max(i - 1, 0)] + 2.0 * levels[i] + levels[min(i + 1, n - 1)]) * 0.25
		line[i] = Vector2(p * w, cy + sin(p * TAU * 3.0 + t * 1.0) * l * amp * sin(p * PI))
	var col := _tone_color(A.tone)
	var glow: float = (0.06 + A.loudness * 0.3 + A.beat_light * 0.15) * L.intensity * L.glow
	L.draw_polyline(line, Color(col, glow * 0.35), 14.0, true)
	L.draw_polyline(line, Color(col, glow * 0.6), 7.0, true)
	L.draw_polyline(line, Color(col, glow), 3.5, true)
	L.draw_polyline(line, Color(col.lightened(0.35), 0.95), 1.5, true)


func _draw_grid() -> void:
	var levels: PackedFloat32Array = A.levels
	var n := levels.size()
	var area := Rect2(L.size * Vector2(0.15, 0.32), L.size * Vector2(0.7, 0.36))
	var spacing := clampf(area.size.y / 8.0, 14.0, 40.0)
	var cols := int(area.size.x / spacing)
	var rows := int(area.size.y / spacing)
	var origin := area.get_center() - Vector2(cols - 1, rows - 1) * spacing * 0.5
	for c in cols:
		var p := (c + 0.5) / cols
		var e := levels[int(p * (n - 1))]
		var col := _tone_color(clampf(A.tone - (1.0 - p) * 0.12, 0.0, 1.0))
		for r in rows:
			var dist := absf(r - (rows - 1) * 0.5) / maxf(rows * 0.5, 1.0)
			var wobble := 0.88 + 0.12 * sin(t * 0.6 + c * 1.3 + r * 2.1)
			var k: float = clampf((e * 1.3 + A.loudness * 0.4 - dist * 0.7) * wobble, 0.0, 1.0) * L.intensity
			var s := spacing * clampf(0.12 + 0.5 * k, 0.12, 0.8)
			var center := origin + Vector2(c, r) * spacing
			L.draw_rect(Rect2(center - Vector2(s, s), Vector2(s, s) * 2.0), Color(col, 0.07 * k * L.glow))
			L.draw_rect(Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s)), Color(col.lightened(0.2), 0.3 + 0.5 * minf(k, 1.0)))


func _draw_seven_waves() -> void:
	var spacing := L.size.y * 0.6 / 7.0
	var points := Common.pick(70, 110, 160)
	if line.size() != points:
		line.resize(points)
	for i in 7:
		var e: float = A.bands7[i]
		var base_y := L.size.y * 0.2 + spacing * (i + 0.5)
		var amp: float = spacing * (0.06 + 0.5 * e) * L.intensity
		for j in points:
			var p := float(j) / (points - 1)
			var wave := sin(p * TAU * (1.5 + i * 0.35) + t * (0.9 + i * 0.15)) * 0.75 + sin(p * TAU * 4.1 - t * 1.3 + i) * 0.25
			line[j] = Vector2(p * L.size.x, base_y + wave * amp * sin(p * PI))
		var col: Color = Common.BAND_COLORS[i]
		var glow: float = (0.08 + 0.25 * e) * L.intensity * L.glow
		L.draw_polyline(line, Color(col, glow * 0.4), 10.0, true)
		L.draw_polyline(line, Color(col, glow), 4.0, true)
		L.draw_polyline(line, Color(col.lightened(0.3), 0.9), 1.5, true)


func _update_retro(delta: float) -> void:
	var levels: PackedFloat32Array = A.levels
	var per: int = levels.size() / RETRO_COLS
	for c in RETRO_COLS:
		var target := 0.0
		for i in range(c * per, (c + 1) * per):
			target = maxf(target, levels[i])
		target = clampf(target * L.intensity, 0.0, 1.0)
		retro_height[c] = maxf(target, retro_height[c] - delta * 1.4)
		if retro_height[c] >= retro_peak[c]:
			retro_peak[c] = retro_height[c]
			retro_hold[c] = 0.6
		elif retro_hold[c] > 0.0:
			retro_hold[c] -= delta
		else:
			retro_peak[c] = maxf(retro_peak[c] - delta * 0.7, retro_height[c])


func _draw_retro() -> void:
	var area := Rect2(L.size * Vector2(0.12, 0.22), L.size * Vector2(0.76, 0.56))
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
			var rect := Rect2(origin + Vector2(c * cell, (RETRO_ROWS - 1 - r) * cell), Vector2(block, block))
			if r < lit or r == peak_row:
				L.draw_rect(rect.grow(block * 0.15), Color(col, 0.12 * L.glow))
				L.draw_rect(rect, Color(col, 0.95))
			else:
				L.draw_rect(rect, Color(0.1, 0.12, 0.1, 0.5))


func _draw_orbs() -> void:
	var scale_factor := L.size.y / 941.0
	for i in 7:
		var e: float = A.bands7[i]
		var drift := Vector2(sin(t * 0.43 + i * 1.9) * 10.0, sin(t * 0.61 + i * 1.3) * 14.0) * scale_factor
		var pos := Vector2(L.size.x * (i + 0.5) / 7.0, L.size.y * 0.55 - e * L.size.y * 0.18 * L.intensity) + drift
		var r: float = (14.0 + e * 22.0 * L.intensity) * scale_factor
		var col: Color = Common.BAND_COLORS[i]
		Common.draw_soft(L, pos, r * 3.6, Color(col, (0.25 + 0.4 * e) * L.glow))
		L.draw_circle(pos, r, Color(col, 0.55 + 0.35 * e))
		L.draw_circle(pos, r * 0.5, Color(col.lightened(0.55), 0.85))

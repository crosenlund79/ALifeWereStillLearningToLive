extends Node
## Shared audio analysis for every visual layer.
##
## Owns the Master bus effect chain, created exactly once: [EQ21 -> SpectrumAnalyzer].
## The analyzer therefore sees the audible, equalised signal. Bus volume/mute is applied
## after effects, so the volume control does not change how strongly visuals react.
##
## Each frame it reads one set of spectrum magnitudes and derives:
##  - `levels` (160 log-spaced bins) and `bands7` (EQ band energies) for the classic modes
##  - named ranges: sub, bass, low_mid, mid, upper_mid, treble, air (0..1, smoothed)
##  - loudness, slow energy, energy change, peaks, silence
##  - transients: `onset` (broadband), `kick` (low), `snap` (high), `beat` (estimated beat)
## Values are normalised by a bounded automatic gain (or a fixed reference when adaptive
## sensitivity is off), gated below the noise floor and smoothed with attack/release.

signal beat_detected(strength: float)

const POINTS := 160
const MIN_HZ := 40.0
const MAX_HZ := 12000.0
const EQ_HZ := [60.0, 150.0, 400.0, 1000.0, 2400.0, 6000.0, 15000.0]
const RANGE_NAMES := ["sub", "bass", "low_mid", "mid", "upper_mid", "treble", "air"]
const RANGE_HZ := [[20.0, 60.0], [60.0, 250.0], [250.0, 500.0], [500.0, 2000.0], [2000.0, 4000.0], [4000.0, 8000.0], [8000.0, 16000.0]]
# Attack / release rates per range: low end is weightier, highs are quicker.
const ATTACK := [16.0, 18.0, 20.0, 22.0, 26.0, 30.0, 32.0]
const RELEASE := [3.5, 4.0, 5.0, 5.5, 7.0, 8.0, 9.0]
const FLOOR_DB := -78.0  # Below this the analyzer is treated as silent.
const RANGE_DB := 66.0
const GATE := 0.06  # Normalised values below this are noise floor and are suppressed.
const MIN_REF := 0.35  # The automatic gain never boosts more than 1 / MIN_REF.
const STEP := 1.0 / 60.0  # Transient analysis rate.
const FLUX_FLOOR := [1.0, 0.8, 2.0]  # Minimum low / high / broadband flux for a transient.

## User sensitivity (0..2, from the Studio) and per-song multiplier.
var sensitivity := 1.0
var song_sensitivity := 1.0
## Adaptive gain follows each range's recent peak; off = fixed reference level.
var adaptive := true

var eq := AudioEffectEQ21.new()
var analyzer := AudioEffectSpectrumAnalyzer.new()
var available := false  # Analyzer instance present and returning data.
## "player": TinserBox's own playback (Master bus). "system": audio captured from other
## apps, played on the silent "Capture" bus, which has its own analyzer.
var source := "player"
var capture_analyzer: AudioEffectSpectrumAnalyzer

# Outputs (all 0..1 unless noted).
var levels := PackedFloat32Array()
var bands7 := PackedFloat32Array()
var ranges := PackedFloat32Array()  # Indexed like RANGE_NAMES.
var sub := 0.0
var bass := 0.0
var low_mid := 0.0
var mid := 0.0
var upper_mid := 0.0
var treble := 0.0
var air := 0.0
var loudness := 0.0  # Smoothed overall level.
var energy_slow := 0.0  # Long-term average of loudness (~4 s).
var energy_delta := 0.0  # loudness - energy_slow (-1..1): crescendos are positive.
var peak := 0.0  # Recent loudness peak (slow release).
var onset := 0.0  # Broadband transient strength, decays quickly.
var kick := 0.0  # Low-frequency impact impulse.
var snap := 0.0  # High-frequency transient impulse (hi-hats, plucks, consonants).
var beat := 0.0  # Estimated beat impulse (1 on a beat, decays).
var beat_light := 0.0  # Rate-limited beat flash amount for shared lighting.
var beat_count := 0
var tempo_bpm := 0.0  # Rough estimate from recent beat intervals (not a precise tracker).
var silence := true
var silence_amount := 1.0  # 1 = silent, 0 = active; smoothed.
var tone := 1.0  # Slow hue drift: 1 toward vocals/mid, 0 toward bass/treble dominance.
var flux := Vector3.ZERO  # Raw spectral flux (low, high, all) for diagnostics.
var time := 0.0  # Audio-weighted time: advances faster with loudness, for organic motion.

# Internal state (preallocated).
var _bin_hz := PackedFloat32Array()
var _bin_tilt := PackedFloat32Array()
var _raw := PackedFloat32Array()
var _prev := PackedFloat32Array()
var _range_raw := PackedFloat32Array()
var _range_peak := PackedFloat32Array()
var _band_peak := PackedFloat32Array()
var _flux_avg := [0.0, 0.0, 0.0]  # low, high, full
var _flux_var := [0.01, 0.01, 0.01]
var _step_acc := 0.0
var _since_kick := 1.0
var _since_snap := 1.0
var _since_beat := 1.0
var _since_flash := 1.0
var _quiet_time := 0.0
var _suppress := 0.0
var _beat_times: Array[float] = []
var _vocal_avg := 0.33
var _loud_peak := 0.5
var _clock := 0.0

# Song personality statistics (reset per track).
var stats_time := 0.0
var stats := {}


func _ready() -> void:
	# Build the chain once; if a previous instance already added effects, reuse them.
	for i in AudioServer.get_bus_effect_count(0):
		var e := AudioServer.get_bus_effect(0, i)
		if e is AudioEffectEQ21:
			eq = e
		elif e is AudioEffectSpectrumAnalyzer:
			analyzer = e
	if _effect_index(eq) < 0:
		AudioServer.add_bus_effect(0, eq, 0)
	if _effect_index(analyzer) < 0:
		analyzer.buffer_length = 0.1
		analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
		AudioServer.add_bus_effect(0, analyzer)

	levels.resize(POINTS)
	_raw.resize(POINTS)
	_prev.resize(POINTS)
	_bin_hz.resize(POINTS + 1)
	_bin_tilt.resize(POINTS)
	for i in POINTS + 1:
		_bin_hz[i] = MIN_HZ * pow(MAX_HZ / MIN_HZ, float(i) / POINTS)
	for i in POINTS:
		# Frequency-dependent sensitivity: music has less energy up high, so tilt +3 dB/octave.
		_bin_tilt[i] = 3.0 * log(sqrt(_bin_hz[i] * _bin_hz[i + 1]) / 1000.0) / log(2.0)
	bands7.resize(7)
	_band_peak.resize(7)
	_band_peak.fill(0.5)
	ranges.resize(7)
	_range_raw.resize(7)
	_range_peak.resize(7)
	_range_peak.fill(0.5)
	reset_song_stats()


## The silent bus for captured system audio: analyzed, never heard (-80 dB after effects).
func capture_bus() -> String:
	if AudioServer.get_bus_index("Capture") < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Capture")
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_volume_db(idx, -80.0)
		capture_analyzer = AudioEffectSpectrumAnalyzer.new()
		capture_analyzer.buffer_length = 0.1
		capture_analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
		AudioServer.add_bus_effect(idx, capture_analyzer)
	return "Capture"


func set_source(new_source: String) -> void:
	source = new_source
	suppress_transients(0.6)
	reset_song_stats()


func _effect_index(effect: AudioEffect) -> int:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == effect:
			return i
	return -1


## Called on seeks and track changes so the jump in spectrum is not read as a transient.
func suppress_transients(seconds := 0.35) -> void:
	_suppress = maxf(_suppress, seconds)


func reset_song_stats() -> void:
	stats_time = 0.0
	stats = {"loud": 0.0, "bass": 0.0, "treble": 0.0, "mid": 0.0, "onsets": 0, "loud_sq": 0.0}


## Average characteristics of the current song so far (null until ~12 s analysed).
func personality() -> Dictionary:
	if stats_time < 12.0:
		return {}
	var n := stats_time
	var loud: float = stats.loud / n
	var dyn := sqrt(maxf(stats.loud_sq / n - loud * loud, 0.0))
	return {
		"loudness": loud,
		"bass": stats.bass / n,
		"treble": stats.treble / n,
		"mid": stats.mid / n,
		"onset_rate": float(stats.onsets) / n,
		"dynamics": dyn,
	}


func _db_norm(magnitude: float, tilt: float) -> float:
	if magnitude <= 0.0000001:
		return 0.0
	var v := (linear_to_db(magnitude) + tilt - FLOOR_DB) / RANGE_DB
	return clampf(v, 0.0, 1.0) if is_finite(v) else 0.0


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_clock += delta
	var inst: AudioEffectSpectrumAnalyzerInstance
	if source == "system":
		inst = AudioServer.get_bus_effect_instance(AudioServer.get_bus_index("Capture"), 0) as AudioEffectSpectrumAnalyzerInstance
	else:
		inst = AudioServer.get_bus_effect_instance(0, _effect_index(analyzer)) as AudioEffectSpectrumAnalyzerInstance
	available = inst != null
	if inst == null:
		return

	# 1. Raw normalised spectrum (one magnitude query per bin).
	var frame_peak := 0.0
	for i in POINTS:
		var m := inst.get_magnitude_for_frequency_range(_bin_hz[i], _bin_hz[i + 1]).length()
		var v := _db_norm(m, _bin_tilt[i])
		v = 0.0 if v < GATE else (v - GATE) / (1.0 - GATE)
		_raw[i] = v
		frame_peak = maxf(frame_peak, v)

	# Spectral flux at a fixed 60 Hz step, so detection never depends on the frame rate
	# (the analyzer refreshes per audio chunk, not per rendered frame).
	_step_acc += delta
	var stepped := _step_acc >= STEP
	var flux_low := 0.0
	var flux_high := 0.0
	var flux_all := 0.0
	if stepped:
		_step_acc = fmod(_step_acc, STEP)
		for i in POINTS:
			var rise := maxf(_raw[i] - _prev[i], 0.0)
			_prev[i] = _raw[i]
			flux_all += rise
			if _bin_hz[i] < 160.0:
				flux_low += rise
			elif _bin_hz[i] > 3000.0:
				flux_high += rise
	if stepped:
		flux = Vector3(flux_low, flux_high, flux_all)

	# 2. Named ranges and EQ bands from the same analyzer instance.
	for r in 7:
		var lo: float = RANGE_HZ[r][0]
		var hi: float = RANGE_HZ[r][1]
		var tilt := 3.0 * log(sqrt(lo * hi) / 1000.0) / log(2.0)
		var v := _db_norm(inst.get_magnitude_for_frequency_range(lo, hi).length(), tilt)
		_range_raw[r] = 0.0 if v < GATE else (v - GATE) / (1.0 - GATE)
	var full := _db_norm(inst.get_magnitude_for_frequency_range(30.0, 16000.0).length(), 0.0)

	# 3. Silence: overall level under the floor gate for a moment.
	if full < GATE * 1.5:
		_quiet_time += delta
	else:
		_quiet_time = 0.0
	silence = _quiet_time > 0.35
	silence_amount = _approach(silence_amount, 1.0 if silence else 0.0, 3.0 if silence else 8.0, delta)

	# 4. Bounded automatic gain: references follow peaks up fast and decay slowly (~8 s).
	var gain := sensitivity * song_sensitivity
	var sens_ref := 0.85
	for r in 7:
		_range_peak[r] = maxf(_range_raw[r], _range_peak[r] - delta * 0.06)
		var ref := maxf(_range_peak[r], MIN_REF) if adaptive else sens_ref
		var target := clampf(_range_raw[r] / ref * 0.92 * gain, 0.0, 1.0)
		ranges[r] = _approach(ranges[r], target, ATTACK[r] if target > ranges[r] else RELEASE[r], delta)
	sub = ranges[0]
	bass = ranges[1]
	low_mid = ranges[2]
	mid = ranges[3]
	upper_mid = ranges[4]
	treble = ranges[5]
	air = ranges[6]

	_loud_peak = maxf(frame_peak, _loud_peak - delta * 0.06)
	var bin_ref := maxf(_loud_peak, MIN_REF) if adaptive else sens_ref
	var bin_gain := 0.92 / bin_ref * gain
	var vocal := 0.0
	var other := 0.0
	for i in POINTS:
		var t := clampf(_raw[i] * bin_gain, 0.0, 1.0)
		levels[i] = _approach(levels[i], t, 18.0 if t > levels[i] else 5.0, delta)
		if _bin_hz[i] > 250.0 and _bin_hz[i] < 3000.0:
			vocal += levels[i]
		else:
			other += levels[i]
	for b in 7:
		var hz: float = EQ_HZ[b]
		var v := _db_norm(inst.get_magnitude_for_frequency_range(hz / 1.5, hz * 1.5).length(), 3.0 * log(hz / 1000.0) / log(2.0))
		v = 0.0 if v < GATE else (v - GATE) / (1.0 - GATE)
		_band_peak[b] = maxf(v, _band_peak[b] - delta * 0.06)
		var ref := maxf(_band_peak[b], MIN_REF) if adaptive else sens_ref
		var t := clampf(pow(v / ref, 1.4) * gain, 0.0, 1.0)
		bands7[b] = _approach(bands7[b], t, 16.0 if t > bands7[b] else 4.5, delta)

	# Loudness relative to the recent peak, kept below saturation so crescendos still register.
	var loud_target := clampf(full / maxf(peak, MIN_REF) * 0.8 * gain, 0.0, 1.0) if adaptive else clampf(full / sens_ref * 0.8 * gain, 0.0, 1.0)
	peak = maxf(full, peak - delta * 0.05)
	loudness = _approach(loudness, loud_target * (1.0 - silence_amount), 10.0 if loud_target > loudness else 2.5, delta)
	energy_slow = _approach(energy_slow, loudness, 0.25, delta)
	energy_delta = clampf(loudness - energy_slow, -1.0, 1.0)
	time += delta * (0.35 + loudness * 0.9)

	# 5. Transients from spectral flux against an adaptive mean + deviation threshold.
	_suppress = maxf(_suppress - delta, 0.0)
	_since_kick += delta
	_since_snap += delta
	_since_beat += delta
	_since_flash += delta
	if stepped:
		var fluxes := [flux_low, flux_high, flux_all]
		var strengths := [0.0, 0.0, 0.0]
		for k in 3:
			var f: float = fluxes[k]
			var sd := sqrt(maxf(_flux_var[k], 0.0001))
			var excess: float = f - _flux_avg[k] - 1.6 * sd
			# Below an absolute floor nothing counts: steady pads and noise never pulse.
			strengths[k] = clampf(excess / (3.0 * sd + 0.02), 0.0, 1.0) if f > FLUX_FLOOR[k] else 0.0
			var d: float = f - _flux_avg[k]
			_flux_avg[k] += d * STEP * 1.5
			_flux_var[k] = lerpf(_flux_var[k], d * d, STEP * 1.5)
		var active := not silence and _suppress <= 0.0
		if active and strengths[0] > 0.25 and _since_kick > 0.16 and bass > 0.2:
			kick = maxf(kick, strengths[0])
			_since_kick = 0.0
		if active and strengths[1] > 0.3 and _since_snap > 0.08:
			snap = maxf(snap, strengths[1])
			_since_snap = 0.0
		if active and strengths[2] > 0.2:
			onset = maxf(onset, strengths[2])
		# A beat: a kick or a strong broadband onset, at most ~3.3 per second.
		var beat_strength := maxf(strengths[0] * (0.6 + bass * 0.6), strengths[2] * 0.8)
		if active and beat_strength > 0.35 and _since_beat > 0.3:
			_register_beat(beat_strength)
	kick = maxf(kick - delta * 5.0, 0.0)
	snap = maxf(snap - delta * 7.0, 0.0)
	onset = maxf(onset - delta * 6.0, 0.0)
	beat = maxf(beat - delta * 3.5, 0.0)
	beat_light = maxf(beat_light - delta * 4.0, 0.0)
	if silence:
		kick = 0.0
		snap = 0.0
		onset = 0.0
		beat = 0.0

	# 6. Slow hue drift: vocal range vs the rest, relative to its own average.
	if vocal + other > 1.0:
		var share := vocal / (vocal + other)
		_vocal_avg = lerpf(_vocal_avg, share, 1.0 - exp(-delta * 0.15))
		var target_tone := 1.0 - 0.5 * clampf(0.5 - (share - _vocal_avg) * 6.0, 0.0, 1.0)
		tone = lerpf(tone, target_tone, 1.0 - exp(-delta * 1.0))

	# 7. Song personality statistics (only while music is audible).
	if not silence:
		stats_time += delta
		stats.loud += loudness * delta
		stats.loud_sq += loudness * loudness * delta
		var total := bass + mid + treble + 0.001
		stats.bass += bass / total * delta
		stats.mid += mid / total * delta
		stats.treble += treble / total * delta


func _register_beat(strength: float) -> void:
	beat = 1.0
	beat_count += 1
	stats.onsets += 1
	_since_beat = 0.0
	# Rapid beats produce gentler flashes, so fast percussion never strobes.
	var flash_gain := clampf(_since_flash / 0.6, 0.25, 1.0)
	beat_light = maxf(beat_light, clampf(strength, 0.4, 1.0) * flash_gain)
	_since_flash = 0.0
	_beat_times.append(_clock)
	if _beat_times.size() > 12:
		_beat_times.pop_front()
	if _beat_times.size() >= 5:
		var intervals: Array[float] = []
		for i in range(1, _beat_times.size()):
			intervals.append(_beat_times[i] - _beat_times[i - 1])
		intervals.sort()
		var median := intervals[intervals.size() / 2]
		if median > 0.25 and median < 1.5:
			tempo_bpm = 60.0 / median
	beat_detected.emit(strength)


func _approach(current: float, target: float, rate: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * delta))


## Named range accessor for presets and debugging.
func range_value(range_name: String) -> float:
	var i := RANGE_NAMES.find(range_name)
	return ranges[i] if i >= 0 else 0.0

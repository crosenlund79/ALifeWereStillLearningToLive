extends RefCounted
## Visualizer presets: built-ins defined here (always recoverable) plus user presets and
## edited built-ins stored in presets.json next to settings.cfg:
##   {"schema": 1, "presets": [ {preset}, ... ], "hidden_builtins": ["name", ...]}
## A preset describes the whole scene: main + secondary layer, atmosphere, beat light,
## background effects and colours. Missing keys fall back to DEFAULT, so older or
## hand-edited files keep working.

const SCHEMA := 1

const LAYER_DEFAULT := {
	"mode": "none", "opacity": 1.0, "scale": 1.0, "intensity": 1.0, "speed": 1.0, "glow": 1.0, "trail": 0.5, "additive": true,
	# Visualizer-specific (each mode reads the ones it needs; see visual_layer.gd MODE_PARAMS).
	"count": 7, "size": 1.0, "thickness": 1.0, "range": 1.0, "response": 1.0, "spacing": 1.0, "depth": 1.0, "density": 1.0,
}
## Default colours for multi-element visualizers (lines, spirits, rings, ribbons, blocks...).
const PALETTE := ["#ffcc66", "#ff9952", "#f57585", "#c785f5", "#75a3ff", "#5cdbdb", "#8ff299"]
const DEFAULT := {
	"name": "Untitled",
	"main": {"mode": "waveform"},
	"secondary": {"mode": "none", "opacity": 0.4},
	"atmosphere": {"mode": "none", "opacity": 0.7},
	"beat_light": 0.0,
	"background": {"kenburns": 0.4, "parallax": 0.3, "breathing": 0.4, "vignette": 0.45, "dim": 0.15, "wash": 0.0, "blur": 0.0, "bloom": 0.2, "shimmer": 0.2},
	"colors": ["#ffd173", "#cc8052"],
	"palette": PALETTE,
}

static func builtins() -> Array:
	return [
		{
			"name": "Midnight Aurora",
			"main": {"mode": "aurora", "intensity": 1.0, "glow": 1.1, "speed": 0.9},
			"secondary": {"mode": "particles", "opacity": 0.3, "intensity": 0.8, "trail": 0.3, "speed": 0.7},
			"atmosphere": {"mode": "dust", "opacity": 0.6},
			"beat_light": 0.15,
			"background": {"kenburns": 0.5, "parallax": 0.3, "breathing": 0.4, "vignette": 0.65, "dim": 0.45, "wash": 0.25, "blur": 0.15, "bloom": 0.25, "shimmer": 0.3},
			"colors": ["#5cf2b8", "#8a66ff"],
		},
		{
			"name": "Stellar Drift",
			"main": {"mode": "particles", "intensity": 1.0, "glow": 1.0, "trail": 0.6, "speed": 0.9},
			"secondary": {"mode": "none"},
			"atmosphere": {"mode": "glow", "opacity": 0.6},
			"beat_light": 0.1,
			"background": {"kenburns": 0.6, "parallax": 0.4, "breathing": 0.6, "vignette": 0.7, "dim": 0.62, "wash": 0.25, "blur": 0.3, "bloom": 0.1, "shimmer": 0.4},
			"colors": ["#ffe0a3", "#6f8cff"],
		},
		{
			"name": "Clockwork Heart",
			"main": {"mode": "resonance", "intensity": 1.0, "glow": 1.0, "speed": 1.0},
			"secondary": {"mode": "particles", "opacity": 0.22, "intensity": 0.7, "trail": 0.2, "speed": 0.6},
			"atmosphere": {"mode": "none"},
			"beat_light": 0.3,
			"background": {"kenburns": 0.3, "parallax": 0.2, "breathing": 0.5, "vignette": 0.6, "dim": 0.45, "wash": 0.15, "blur": 0.1, "bloom": 0.25, "shimmer": 0.2},
			"colors": ["#ffcc66", "#d9774a"],
		},
		{
			"name": "Seven Souls",
			"main": {"mode": "spirits", "intensity": 1.0, "glow": 1.0, "trail": 0.7, "speed": 1.0},
			"secondary": {"mode": "aurora", "opacity": 0.28, "intensity": 0.7, "speed": 0.7},
			"atmosphere": {"mode": "dust", "opacity": 0.5},
			"beat_light": 0.1,
			"background": {"kenburns": 0.5, "parallax": 0.3, "breathing": 0.4, "vignette": 0.6, "dim": 0.48, "wash": 0.12, "blur": 0.15, "bloom": 0.15, "shimmer": 0.3},
			"colors": ["#ffd173", "#9a7cff"],
		},
		{
			"name": "Neon Pulse",
			"main": {"mode": "waveform", "count": 5, "intensity": 1.3, "glow": 1.5, "speed": 1.2, "thickness": 1.2},
			"secondary": {"mode": "pulse_rings", "opacity": 0.3, "intensity": 0.8},
			"atmosphere": {"mode": "glow", "opacity": 0.5},
			"beat_light": 0.5,
			"background": {"kenburns": 0.3, "parallax": 0.2, "breathing": 0.7, "vignette": 0.7, "dim": 0.55, "wash": 0.35, "blur": 0.2, "bloom": 0.35, "shimmer": 0.5},
			"colors": ["#ff4fd8", "#35e0ff"],
			"palette": ["#ff4fd8", "#b45cff", "#5c7cff", "#35e0ff", "#3dffb5", "#ffe14f", "#ff8a3d"],
		},
		{
			"name": "Almost Nothing",
			"main": {"mode": "waveform", "count": 1, "intensity": 0.55, "glow": 0.7, "speed": 0.7, "opacity": 0.8},
			"secondary": {"mode": "none"},
			"atmosphere": {"mode": "dust", "opacity": 0.35},
			"beat_light": 0.0,
			"background": {"kenburns": 0.35, "parallax": 0.2, "breathing": 0.2, "vignette": 0.4, "dim": 0.1, "wash": 0.0, "blur": 0.0, "bloom": 0.15, "shimmer": 0.15},
			"colors": ["#ffd173", "#cc8052"],
			"palette": ["#ffd173", "#e8a85c", "#cc8052", "#ffd173", "#e8a85c", "#cc8052", "#ffd173"],
		},
		{
			"name": "Silk Harmonics",
			"main": {"mode": "ribbons", "count": 4, "glow": 1.1, "speed": 0.9},
			"secondary": {"mode": "particles", "opacity": 0.25, "intensity": 0.7, "density": 0.6},
			"atmosphere": {"mode": "dust", "opacity": 0.4},
			"beat_light": 0.1,
			"background": {"kenburns": 0.5, "parallax": 0.4, "breathing": 0.4, "vignette": 0.65, "dim": 0.55, "wash": 0.2, "blur": 0.35, "bloom": 0.15, "shimmer": 0.3},
			"colors": ["#ffd9a0", "#8f7cff"],
			"palette": ["#ffcf7a", "#ff8f8f", "#c48cff", "#7fb8ff", "#7ff0d2", "#ffe39a", "#ff9fd4"],
		},
		{
			"name": "Echo Chamber",
			"main": {"mode": "pulse_rings", "count": 6, "glow": 1.1},
			"secondary": {"mode": "spirits", "opacity": 0.35, "size": 0.7},
			"atmosphere": {"mode": "glow", "opacity": 0.45},
			"beat_light": 0.2,
			"background": {"kenburns": 0.3, "parallax": 0.3, "breathing": 0.6, "vignette": 0.7, "dim": 0.58, "wash": 0.25, "blur": 0.3, "bloom": 0.15, "shimmer": 0.3},
			"colors": ["#ffcc66", "#5cdbdb"],
		},
		{
			"name": "Polar Night",
			"main": {"mode": "northern_lights", "count": 3, "glow": 1.0, "speed": 0.9},
			"secondary": {"mode": "particles", "opacity": 0.3, "intensity": 0.6, "density": 0.5, "size": 0.7},
			"atmosphere": {"mode": "none"},
			"beat_light": 0.05,
			"background": {"kenburns": 0.4, "parallax": 0.3, "breathing": 0.3, "vignette": 0.7, "dim": 0.7, "wash": 0.3, "blur": 0.4, "bloom": 0.05, "shimmer": 0.2},
			"colors": ["#4dffa6", "#a64dff"],
			"palette": ["#4dffa6", "#33e0c0", "#7dff7a", "#4dd2ff", "#a64dff", "#ff7ad9", "#ffe17a"],
		},
		{
			"name": "Golden Thread",
			"main": {"mode": "waveform", "count": 1, "additive": false},
			"secondary": {"mode": "none"},
			"atmosphere": {"mode": "none"},
			"beat_light": 0.0,
			"background": {"kenburns": 0.0, "parallax": 0.0, "breathing": 0.0, "vignette": 0.0, "dim": 0.0, "wash": 0.0, "blur": 0.0, "bloom": 0.0, "shimmer": 0.0},
			"colors": ["#ffd173", "#cc8052"],
			"palette": ["#ffd173", "#ff9952", "#f57585", "#c785f5", "#75a3ff", "#5cdbdb", "#8ff299"],
		},
	]


static func builtin_names() -> Array:
	return builtins().map(func(p): return p.name)


## Fill in every missing key so code can rely on a complete preset.
static func complete(p: Dictionary) -> Dictionary:
	p = p.duplicate(true)
	# Migrate visualizers that were merged or removed in TinserBox 2.1.
	for layer in ["main", "secondary"]:
		var l = p.get(layer)
		if l is Dictionary:
			if l.get("mode") == "seven_waves":
				l.mode = "waveform"
				l.count = l.get("count", 7)
			elif l.get("mode") == "orbs":
				l.mode = "spirits"
			elif l.get("mode") == "waveform" and not l.has("count"):
				l.count = 1
	var out: Dictionary = DEFAULT.duplicate(true)
	for k in p:
		if out.get(k) is Dictionary and p[k] is Dictionary:
			out[k].merge(p[k], true)
		else:
			out[k] = p[k]
	for layer in ["main", "secondary", "atmosphere"]:
		var merged: Dictionary = LAYER_DEFAULT.duplicate()
		merged.merge(out[layer], true)
		out[layer] = merged
	return out


var path := ""
var user_presets: Array = []
var hidden_builtins: Array = []


func load_file(file_path: String) -> void:
	path = file_path
	user_presets = []
	hidden_builtins = []
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and int(data.get("schema", 0)) >= 1:
		for p in data.get("presets", []):
			if p is Dictionary and p.has("name"):
				user_presets.append(p)
		hidden_builtins = data.get("hidden_builtins", [])


func save_file() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"schema": SCHEMA, "presets": user_presets, "hidden_builtins": hidden_builtins}, "\t"))


## All visible presets: built-ins (user edits replace them by name) then user presets.
func all() -> Array:
	var out := []
	for b in builtins():
		if b.name in hidden_builtins:
			continue
		var edited = _user(b.name)
		var p: Dictionary = edited if edited != null else b
		p = complete(p)
		p["builtin"] = true
		out.append(p)
	for u in user_presets:
		if not (u.name in builtin_names()):
			var p := complete(u)
			p["builtin"] = false
			out.append(p)
	return out


func names() -> Array:
	return all().map(func(p): return p.name)


func get_preset(preset_name: String) -> Dictionary:
	for p in all():
		if p.name == preset_name:
			return p
	return {}


func _user(preset_name: String):
	for u in user_presets:
		if u.name == preset_name:
			return u
	return null


## Save (create or overwrite) a preset by name. Built-in names store an edited copy.
func save_preset(p: Dictionary) -> void:
	var clean := p.duplicate(true)
	clean.erase("builtin")
	for i in user_presets.size():
		if user_presets[i].name == clean.name:
			user_presets[i] = clean
			save_file()
			return
	user_presets.append(clean)
	hidden_builtins.erase(clean.name)
	save_file()


func unique_name(base: String) -> String:
	var existing := names()
	if not (base in existing):
		return base
	var n := 2
	while "%s %d" % [base, n] in existing:
		n += 1
	return "%s %d" % [base, n]


func rename_preset(old_name: String, new_name: String) -> bool:
	if old_name in builtin_names() or new_name.strip_edges() == "" or new_name in names():
		return false
	for u in user_presets:
		if u.name == old_name:
			u.name = new_name
			save_file()
			return true
	return false


func delete_preset(preset_name: String) -> bool:
	if preset_name in builtin_names():
		# Built-ins can be hidden; "Restore built-ins" brings them back.
		hidden_builtins.append(preset_name)
		var edited = _user(preset_name)
		if edited != null:
			user_presets.erase(edited)
		save_file()
		return true
	var u = _user(preset_name)
	if u == null:
		return false
	user_presets.erase(u)
	save_file()
	return true


## Restore built-ins: unhide them and discard edits made to them (user presets are kept).
func restore_builtins() -> void:
	hidden_builtins.clear()
	var keep := []
	for u in user_presets:
		if not (u.name in builtin_names()):
			keep.append(u)
	user_presets = keep
	save_file()

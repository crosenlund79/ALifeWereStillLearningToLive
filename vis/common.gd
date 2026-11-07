extends RefCounted
## Shared helpers for visual renderers: quality level, soft glow texture, band colours.

const BAND_COLORS := [
	Color(1.0, 0.80, 0.40), Color(1.0, 0.60, 0.32), Color(0.96, 0.46, 0.52), Color(0.78, 0.52, 0.96),
	Color(0.46, 0.64, 1.0), Color(0.36, 0.86, 0.86), Color(0.56, 0.95, 0.60),
]

enum Quality { PERFORMANCE, BALANCED, QUALITY }

static var quality := Quality.BALANCED
static var _soft: Texture2D


## 0.0 (performance) .. 1.0 (quality), for scaling counts and detail.
static func q() -> float:
	return float(quality) / 2.0


static func pick(performance: int, balanced: int, best: int) -> int:
	return [performance, balanced, best][quality]


## White radial falloff texture used for every soft glow, dot and halo (created once).
static func soft_texture() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.55))
		g.add_point(0.6, Color(1, 1, 1, 0.12))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 128
		tex.height = 128
		_soft = tex
	return _soft


static func draw_soft(item: CanvasItem, pos: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.1 or color.a <= 0.002:
		return
	item.draw_texture_rect(soft_texture(), Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)


## Frame-rate independent exponential approach.
static func approach(current: float, target: float, rate: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * delta))

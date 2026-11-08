shader_type canvas_item;
// Lights a dancer sprite with the visualizer's own lights.
// Each light (screen position, colour, strength) adds a soft fill, and a rim on the
// silhouette edges that face it. Edge direction comes from the sprite's alpha gradient,
// so different sides of the body pick up different colours. Transparency and the
// character's own colours are kept: light is only added on top, scaled by `strength`.

uniform int light_count = 0;
uniform vec2 light_pos[10];
uniform vec4 light_col[10];  // rgb = colour, a = intensity (0..~1.5)
uniform float strength = 0.6;  // user lighting strength 0..1
uniform vec2 tex_px = vec2(0.004, 0.002);  // 1 / texture size
uniform float screen_h = 941.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (base.a < 0.004 || strength <= 0.0) {
		COLOR = base * COLOR;
	} else {
		// Outward edge normal from the alpha gradient (sampled a few texels away).
		vec2 o = tex_px * 6.0;
		float a_l = texture(TEXTURE, UV - vec2(o.x, 0.0)).a;
		float a_r = texture(TEXTURE, UV + vec2(o.x, 0.0)).a;
		float a_u = texture(TEXTURE, UV - vec2(0.0, o.y)).a;
		float a_d = texture(TEXTURE, UV + vec2(0.0, o.y)).a;
		vec2 n = vec2(a_l - a_r, a_u - a_d);
		float edge = clamp(length(n), 0.0, 1.0);
		n = edge > 0.001 ? normalize(n) : vec2(0.0);
		vec3 fill = vec3(0.0);
		vec3 rim = vec3(0.0);
		for (int i = 0; i < 10; i++) {
			if (i >= light_count) break;
			vec2 d = light_pos[i] - world;
			float dist = length(d) / screen_h;
			vec2 dir = d / max(length(d), 1.0);
			float fall = light_col[i].a / (1.0 + 7.0 * dist * dist);
			fill += light_col[i].rgb * fall;
			rim += light_col[i].rgb * fall * max(dot(n, dir), 0.0) * edge;
		}
		// Fill tints the body, a little light spills onto dark surfaces, rims catch colour.
		vec3 lit = base.rgb + base.rgb * fill * 0.6 * strength + fill * 0.16 * strength + rim * 2.2 * strength;
		COLOR = vec4(lit, base.a) * COLOR;
	}
}

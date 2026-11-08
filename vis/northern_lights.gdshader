shader_type canvas_item;
render_mode blend_add;
// Northern Lights: hanging curtains of vertical rays over a star field (additive light).

uniform float t = 0.0;
uniform int count = 3;
uniform vec4 energy = vec4(0.0);     // per curtain, 0..1
uniform float treble = 0.0;
uniform float loud = 0.0;
uniform float flash = 0.0;
uniform float glow = 1.0;
uniform float move = 1.0;
uniform float aspect = 1.78;
uniform vec4 col0 : source_color = vec4(0.3, 1.0, 0.65, 1.0);
uniform vec4 col1 : source_color = vec4(0.2, 0.85, 0.75, 1.0);
uniform vec4 col2 : source_color = vec4(0.5, 1.0, 0.45, 1.0);
uniform vec4 col3 : source_color = vec4(0.3, 0.8, 1.0, 1.0);
uniform vec4 top_col : source_color = vec4(0.65, 0.3, 1.0, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// Brightness of curtain k at uv, plus how far above its lower edge we are.
vec2 curtain(vec2 uv, float k, float e) {
	float x = uv.x * aspect;
	float base = 0.30 + 0.09 * k
		+ 0.06 * sin(x * 1.3 + t * 0.07 * (1.0 + k) + k * 2.0) * move
		+ 0.03 * sin(x * 3.1 - t * 0.11 + k) * move * (0.5 + e);
	float fx = x + 0.25 * sin(x * 0.9 + t * 0.05 + k * 1.7) * move;
	float above = base - uv.y;
	if (above < -0.03) return vec2(0.0);
	float lower = smoothstep(-0.03, 0.01, above);
	float height = 0.09 + 0.16 * e + 0.03 * k;
	float fall = exp(-max(above, 0.0) / height);
	float rays = noise(vec2(fx * 26.0 + k * 13.0, t * 0.22 * (0.6 + treble)));
	rays = 0.35 + 0.65 * pow(rays, 1.4);
	float shimmer = 0.85 + 0.15 * sin(fx * 90.0 + t * (2.0 + 6.0 * treble));
	float edge = 1.0 + 1.2 * exp(-max(above, 0.0) / 0.02);  // bright lower hem
	return vec2(lower * fall * rays * shimmer * edge * (0.22 + 0.8 * e), max(above, 0.0));
}

void fragment() {
	vec2 uv = UV;
	vec3 c = vec3(0.0);
	for (int k = 0; k < 4; k++) {
		if (k >= count) break;
		float e = energy[k];
		vec3 base_col = k == 0 ? col0.rgb : (k == 1 ? col1.rgb : (k == 2 ? col2.rgb : col3.rgb));
		vec2 v = curtain(uv, float(k), e);
		// Green-ish at the lower edge, shifting toward the top colour higher up.
		vec3 col = mix(base_col, top_col.rgb, smoothstep(0.04, 0.3, v.y));
		c += col * v.x * (0.85 - 0.1 * float(k));
	}
	// Stars, fading toward the horizon.
	vec2 sp = uv * vec2(aspect, 1.0) * 110.0;
	vec2 cell = floor(sp);
	float h = hash(cell);
	float star = step(0.986, h) * smoothstep(0.35, 0.0, length(fract(sp) - 0.5));
	star *= (0.55 + 0.45 * sin(t * 1.7 + h * 60.0)) * (1.0 - smoothstep(0.25, 0.7, uv.y));
	c += vec3(star) * 0.45;
	c *= glow * (0.7 + 0.45 * loud + 0.25 * flash);
	COLOR = vec4(c, COLOR.a);
}

shader_type canvas_item;
// TinserBox living background: crossfade, cover-fit, Ken Burns, blur, bloom, shimmer,
// colour wash, dimming, vignette and a procedural fallback, in one pass.

uniform sampler2D tex_a : filter_linear_mipmap, repeat_disable;
uniform sampler2D tex_b : filter_linear_mipmap, repeat_disable;
uniform float mix_ab = 1.0;          // 0 = previous image (b), 1 = current (a)
uniform vec2 size_a = vec2(16.0, 9.0);
uniform vec2 size_b = vec2(16.0, 9.0);
uniform bool proc_a = false;
uniform bool proc_b = false;
uniform vec2 screen = vec2(1672.0, 941.0);
uniform float zoom = 1.0;
uniform vec2 pan = vec2(0.0);
uniform float blur = 0.0;            // mip level
uniform float bloom = 0.0;
uniform float shimmer = 0.0;
uniform float dim = 0.0;
uniform float wash = 0.0;
uniform vec4 wash_color : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform float vignette = 0.0;
uniform float t = 0.0;
uniform vec4 proc_c1 : source_color = vec4(0.05, 0.12, 0.09, 1.0);
uniform vec4 proc_c2 : source_color = vec4(0.45, 0.32, 0.12, 1.0);

vec2 cover(vec2 uv, vec2 tex_size) {
	float sa = screen.x / screen.y;
	float ta = tex_size.x / tex_size.y;
	vec2 s = sa > ta ? vec2(1.0, ta / sa) : vec2(sa / ta, 1.0);
	return (uv - 0.5) * s / zoom + 0.5 + pan;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

vec3 procedural(vec2 uv) {
	vec2 p = (uv - 0.5) * vec2(screen.x / screen.y, 1.0) / zoom + pan * 3.0;
	float n = fbm(p * 2.2 + vec2(t * 0.012, -t * 0.008));
	float n2 = fbm(p * 4.0 - vec2(t * 0.02, t * 0.01) + n);
	vec3 base = mix(proc_c1.rgb * 0.35, proc_c1.rgb, smoothstep(0.2, 0.8, n));
	base += proc_c2.rgb * pow(n2, 3.0) * 0.6;
	base += proc_c2.rgb * 0.18 * exp(-6.0 * dot(uv - vec2(0.5, 0.6), uv - vec2(0.5, 0.6)));
	return base;
}

vec3 sample_image(sampler2D tex, vec2 tex_size, bool is_proc, vec2 uv) {
	if (is_proc) return procedural(uv);
	vec2 tuv = cover(uv, tex_size);
	vec3 c = textureLod(tex, tuv, blur).rgb;
	if (bloom > 0.001) {
		vec3 wide = textureLod(tex, tuv, blur + 4.5).rgb;
		c += max(wide - 0.45, vec3(0.0)) * bloom * 1.6;
	}
	return c;
}

void fragment() {
	vec2 uv = UV;
	vec3 a = sample_image(tex_a, size_a, proc_a, uv);
	vec3 col = a;
	if (mix_ab < 0.999) {
		vec3 b = sample_image(tex_b, size_b, proc_b, uv);
		col = mix(b, a, smoothstep(0.0, 1.0, mix_ab));
	}
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	if (shimmer > 0.001) {
		float s = noise(uv * vec2(screen.x / screen.y, 1.0) * 24.0 + vec2(t * 0.6, -t * 0.4));
		col *= 1.0 + shimmer * 0.22 * pow(s, 4.0) * smoothstep(0.25, 0.8, luma);
	}
	col = mix(col, wash_color.rgb * (luma * 1.5 + 0.05), wash * 0.6);
	col *= 1.0 - dim;
	float d = length((uv - 0.5) * vec2(screen.x / screen.y, 1.0)) / length(vec2(screen.x / screen.y, 1.0) * 0.5);
	col *= 1.0 - vignette * smoothstep(0.35, 1.0, d) * 0.85;
	COLOR = vec4(col, 1.0);
}

shader_type canvas_item;
// Corruption pass for the enemy plates.
//
// The plates are art in their own right and nothing here repaints them: this
// shader only re-lights pixels the illustration already put down. Which pixels
// those are was decided once, offline, by `tools/enemy_cutout.py`, and arrives
// as a mask: red where a lit eye is, green along the corruption cracks, blue
// on the lava toad's fissures. The tier dials are gains on that mask.
//
// The classification is not done here because it cannot be. A lit eye and a
// corruption crack are painted in the same value range (measured: the eye's
// 25th percentile and the crack's median are both 0.49), so no per-pixel
// threshold separates them. What separates them is shape — a blob versus a
// thin network — and a fragment shader has no connected components.

uniform sampler2D rot_mask : hint_default_black;
uniform float eye_gain   : hint_range(0.0, 4.0) = 1.0;
uniform float vein_gain  : hint_range(0.0, 4.0) = 0.0;
uniform float ember_gain : hint_range(0.0, 2.0) = 0.6;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.0;
uniform vec3  rim_color : source_color = vec3(0.81, 0.66, 0.87);
uniform float rim_px = 3.0;

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec3 lit = src.rgb;

	// --- bloom: a 5x5 gather over the mask, so only the eyes, the cracks and
	// the lava contribute anything. The colour comes from the plate itself —
	// the mask only says which pixels are allowed to glow and how hard.
	vec3 glow = vec3(0.0);
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 o = vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE * 1.6;
			vec3 m = texture(rot_mask, UV + o).rgb;
			float g = m.r * eye_gain + m.g * vein_gain + m.b * ember_gain;
			if (g < 0.001) { continue; }
			float w = max(0.0, 1.0 - length(vec2(float(x), float(y))) / 3.2);
			glow += texture(TEXTURE, UV + o).rgb * w * g;
		}
	}
	lit += glow * 0.055;

	// --- rim: lit on the INSIDE of the silhouette. The sprite is trimmed to
	// its alpha bounds and drawn into a rect of exactly that size, so an
	// outward glow would be clipped off. Inward also puts the light straight
	// onto the plate's own heavy ink outline, which is the part that
	// disappears first against a near-black card.
	if (rim_strength > 0.001 && src.a > 0.2) {
		float amin = 1.0;
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.7853981;
			vec2 o = vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE * rim_px;
			amin = min(amin, texture(TEXTURE, UV + o).a);
		}
		float edge = src.a * (1.0 - amin);
		lit = mix(lit, rim_color, clamp(edge * rim_strength, 0.0, 1.0));
	}

	COLOR = vec4(lit, src.a) * COLOR;
}

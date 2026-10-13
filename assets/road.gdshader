// Road slabs: real stone laid across the whole road in world space, so no two slabs look the
// same, with a joint and a lit bevel cut around every cell. The instance colour paints the
// slab; its alpha says how strongly (plain road lightly, take-off strips and the finish fully).
shader_type spatial;

uniform sampler2D stone : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.3;
uniform float roughness = 0.8;
uniform float metallic = 0.0;
uniform float bump = 1.0;

varying vec3 world_pos;
varying vec3 local_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_pos = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	bool top = abs(world_normal.y) > 0.5;
	vec2 uv = top ? world_pos.xz : (abs(world_normal.x) > abs(world_normal.z) ? world_pos.zy : world_pos.xy);
	uv *= scale;
	vec3 rock = texture(stone, uv).rgb;
	float edge = max(abs(local_pos.x), abs(local_pos.z));
	float joint = top ? smoothstep(0.5, 0.462, edge) : 1.0;
	float bevel = top ? smoothstep(0.41, 0.462, edge) * joint : 0.0;
	vec3 paint = mix(vec3(1.0), COLOR.rgb * 1.5, COLOR.a);
	ALBEDO = rock * paint * mix(0.38, 1.0, joint) + vec3(bevel * 0.07);
	NORMAL_MAP = texture(stone_normal, uv).rgb;
	NORMAL_MAP_DEPTH = bump;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.25;
}

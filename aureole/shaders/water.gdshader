shader_type spatial;
render_mode diffuse_burley;
varying vec3 water_position;
void vertex() {
    water_position = VERTEX;
    VERTEX += NORMAL * (sin(VERTEX.x * 5.0 + TIME * 0.48) * sin(VERTEX.y * 6.0 - TIME * 0.35)) * 0.008;
}
void fragment() {
    float wave = sin(water_position.x * 21.0 + TIME * 0.58 + sin(water_position.y * 12.0)) * sin(water_position.z * 17.0 - TIME * 0.32);
    ALBEDO = COLOR.rgb * (0.96 + 0.04 * wave);
    ROUGHNESS = 0.24 + 0.035 * wave;
    METALLIC = 0.28;
    SPECULAR = 0.65;
    NORMAL_MAP = normalize(vec3(0.10 * wave, 0.07 * sin(water_position.y * 28.0 + TIME * 0.4), 1.0)) * 0.5 + 0.5;
    EMISSION = COLOR.rgb * 0.08;
}

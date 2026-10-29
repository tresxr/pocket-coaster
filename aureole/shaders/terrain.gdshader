shader_type spatial;
render_mode diffuse_burley;
varying vec3 sculpt_position;
void vertex() { sculpt_position = VERTEX; }
void fragment() {
    float grain = sin(sculpt_position.x * 173.0 + sin(sculpt_position.z * 121.0)) * sin(sculpt_position.y * 149.0);
    ALBEDO = COLOR.rgb * (0.985 + 0.022 * grain);
    ROUGHNESS = 0.86;
    SPECULAR = 0.28;
    NORMAL_MAP = normalize(vec3(0.025 * grain, 0.018 * sin(sculpt_position.z * 195.0), 1.0)) * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = 0.22;
}

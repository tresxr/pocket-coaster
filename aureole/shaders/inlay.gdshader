shader_type spatial;
void fragment() {
    ALBEDO = COLOR.rgb;
    METALLIC = 0.25;
    ROUGHNESS = 0.3;
    EMISSION = COLOR.rgb * (0.40 + 0.025 * sin(TIME * 0.65));
}

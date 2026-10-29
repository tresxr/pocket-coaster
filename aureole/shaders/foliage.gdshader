shader_type spatial;
render_mode diffuse_burley;
void vertex() {
    float canopy = smoothstep(0.18, 0.6, VERTEX.y);
    VERTEX.x += sin(TIME * 0.65 + MODEL_MATRIX[3].x * 1.8) * 0.009 * canopy;
    VERTEX.z += cos(TIME * 0.49 + MODEL_MATRIX[3].z * 2.1) * 0.006 * canopy;
}
void fragment() {
    ALBEDO = mix(vec3(dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722))), COLOR.rgb, 0.78) * 0.79;
    ROUGHNESS = 0.76;
    SPECULAR = 0.24;
    BACKLIGHT = COLOR.rgb * 0.12;
}

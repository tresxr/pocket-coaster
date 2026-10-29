shader_type sky;
void sky() {
    vec3 d = normalize(EYEDIR);
    float halo = pow(max(0.0, dot(d, normalize(vec3(-0.3, 0.15, -1.0)))), 6.0);
    float veil = pow(max(0.0, dot(d, normalize(vec3(0.7, -0.2, -1.0)))), 18.0);
    COLOR = vec3(0.011, 0.009, 0.025) + vec3(0.029, 0.023, 0.045) * halo + vec3(0.009, 0.021, 0.025) * veil;
}

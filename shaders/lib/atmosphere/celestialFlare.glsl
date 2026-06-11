// sun flare, moon glow

#ifndef CELESTIAL_FLARE_GLSL
#define CELESTIAL_FLARE_GLSL

// Project a world-space direction to screen UV (returns vec3, .z = behind camera)
vec3 worldDirToScreen(vec3 worldDir) {
    vec4 viewPos  = gbufferModelView * vec4(worldDir * 1000.0, 1.0);
    vec4 clipPos  = gbufferProjection * viewPos;
    if (clipPos.w <= 0.0) return vec3(0.0, 0.0, -1.0); // behind camera
    vec3 ndc = clipPos.xyz / clipPos.w;
    return vec3(ndc.xy * 0.5 + 0.5, 1.0);
}

// Starburst: N-pointed spike pattern
float starburst(vec2 delta, int spokes, float sharpness) {
    float angle = atan(delta.y, delta.x);
    float spoke = abs(cos(angle * float(spokes) * 0.5));
    float dist  = length(delta);
    return pow(spoke, sharpness) / (dist * 80.0 + 1.0);
}

// Single lens ring
float lensRing(vec2 delta, float radius, float thickness) {
    float d = abs(length(delta) - radius);
    return smoothstep(thickness, 0.0, d);
}

vec3 getSunFlare(vec2 uv, float depth) {
    if (!isDay) return vec3(0.0);
    // Only draw on sky pixels
    if (depth < 1.0) return vec3(0.0);

    vec3 screen = worldDirToScreen(worldSunDir);
    if (screen.z < 0.0 || worldSunDir.y < -0.05) return vec3(0.0);

    // Hide when sun is below horizon
    float horizonFade = smoothstep(-0.05, 0.1, worldSunDir.y);

    vec2 sunUV  = screen.xy;
    vec2 delta  = (uv - sunUV) * vec2(aspectRatio, 1.0);
    float dist  = length(delta);

    // Core glow
    float core  = 1.0 / (dist * 120.0 + 1.0) * 0.15;

    // Starburst — 8 main spokes + 4 secondary
    float burst8  = starburst(delta, 8,  18.0) * 0.04 * SUN_FLARE_STRENGTH;
    float burst4  = starburst(delta, 4,  32.0) * 0.025 * SUN_FLARE_STRENGTH;
    // Long horizontal streak (anamorphic)
    float streak  = 0.012 / (abs(delta.y) * 200.0 + 1.0)
                  * smoothstep(0.3, 0.0, abs(delta.x))
                  * SUN_FLARE_STRENGTH;

    // Lens ring
    float ring1 = lensRing(delta, 0.08, 0.003) * 0.06 * SUN_FLARE_STRENGTH;
    float ring2 = lensRing(delta, 0.14, 0.002) * 0.03 * SUN_FLARE_STRENGTH;

    float total = (core + burst8 + burst4 + streak + ring1 + ring2) * horizonFade;

    // Warm golden sun color
    vec3 sunColor = vec3(1.0, 0.82, 0.45) * sunlightColor * 2.0;
    return sunColor * total;
}

vec3 getMoonGlow(vec2 uv, float depth) {
    if (isDay) return vec3(0.0);
    if (depth < 1.0) return vec3(0.0);

    vec3 moonWorldDir = -worldSunDir;
    vec3 screen = worldDirToScreen(moonWorldDir);
    if (screen.z < 0.0 || moonWorldDir.y < -0.05) return vec3(0.0);

    float horizonFade = smoothstep(-0.05, 0.1, moonWorldDir.y);

    // Moon phase: full=0, new=4 (moonPhase 0-7, 0=full, 4=new)
    float phaseFactor = 1.0 - abs(float(moonPhase - 4) / 4.0); // 0=new, 1=full
    if (phaseFactor < 0.05) return vec3(0.0);

    vec2 moonUV = screen.xy;
    vec2 delta  = (uv - moonUV) * vec2(aspectRatio, 1.0);
    float dist  = length(delta);

    // Soft outer halo
    float halo = 1.0 / (dist * 60.0 + 1.0) * 0.08 * phaseFactor;
    // Inner glow
    float glow = 1.0 / (dist * 200.0 + 1.0) * 0.05 * phaseFactor;
    // Faint ring
    float ring = lensRing(delta, 0.06, 0.008) * 0.04 * phaseFactor;

    float total = (halo + glow + ring) * horizonFade * MOON_GLOW_STRENGTH;

    // Cool blue-white moon color
    vec3 moonColor = vec3(0.75, 0.85, 1.0) * 1.5;
    return moonColor * total;
}

#endif // CELESTIAL_FLARE_GLSL

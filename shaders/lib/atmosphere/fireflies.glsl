// fireflies

#ifndef FIREFLIES_GLSL
#define FIREFLIES_GLSL

float ffHash(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

vec2 ffHash2(vec3 p) {
    return vec2(ffHash(p), ffHash(p + 7.3));
}

float getFireflyBiomeFactor() {
    vec3 sc = pow(clamp(skyColor, vec3(0.0), vec3(1.0)), vec3(2.2));
    // Exclude nether: skyColor is very red
    float isNether = smoothstep(0.1, 0.3, sc.r - sc.b - sc.g * 0.5);
    // Exclude end: skyColor is dark purple/black — already handled by WORLD_OVERWORLD guard
    // Exclude desert/mesa: skyColor is warm orange (r >> g >> b)
    float isDesert = smoothstep(0.05, 0.15, sc.r - sc.g * 1.2 - sc.b);
    // Exclude snowy: skyColor is very blue-white
    float isSnowy  = smoothstep(0.05, 0.15, sc.b - sc.r - sc.g * 0.3);
    return clamp01(1.0 - isNether - isDesert - isSnowy);
}

vec3 getFireflyPos(vec3 cell, float seed, float t) {
    // Base position in cell
    vec3 base = cell + vec3(
        ffHash(cell),
        ffHash(cell + 1.7) * 0.4 + 0.1, // y: 0.1..0.5 above ground
        ffHash(cell + 3.1)
    );

    // Smooth floating animation — Lissajous-like path
    float speed  = ffHash(cell + seed) * 0.4 + 0.2;
    float phase  = ffHash(cell + seed + 5.5) * 6.28;
    float phase2 = ffHash(cell + seed + 9.1) * 6.28;
    float phase3 = ffHash(cell + seed + 12.7) * 6.28;

    base.x += sin(t * speed       + phase)  * 0.3;
    base.y += sin(t * speed * 1.3 + phase2) * 0.15;
    base.z += cos(t * speed * 0.9 + phase3) * 0.3;

    return base;
}

vec4 worldToScreen(vec3 worldPos) {
    // feetPlayerPos space = worldPos - cameraPosition
    vec3 feetPos = worldPos - cameraPosition;
    // gbufferModelViewInverse goes world->view, we need inverse
    vec4 viewPos = gbufferModelView * vec4(feetPos, 1.0);
    if (viewPos.z > 0.0) return vec4(0.0, 0.0, 0.0, -1.0); // behind camera
    vec4 clip    = gbufferProjection * viewPos;
    if (clip.w <= 0.0) return vec4(0.0, 0.0, 0.0, -1.0);
    vec3 ndc     = clip.xyz / clip.w;
    vec2 screen  = ndc.xy * 0.5 + 0.5;
    return vec4(screen, ndc.z * 0.5 + 0.5, clip.w); // .z = depth 0..1
}

vec3 getFireflies(vec2 uv, sampler2D depthTex) {
    vec3 result = vec3(0.0);

    // Conditions: night, overworld, not in water, not raining heavily
    float nightFactor = clamp01(1.0 - worldSunDir.y * 6.0);
    if (nightFactor < 0.01) return result;

    float biomeFactor = getFireflyBiomeFactor();
    if (biomeFactor < 0.01) return result;

    float rainFade = 1.0 - rainStrength * 0.8;
    float strength = nightFactor * biomeFactor * rainFade * FIREFLY_STRENGTH;
    if (strength < 0.01) return result;

    float t = frameTimeCounter;

    // World-space grid around player — cells of FIREFLY_SPACING blocks
    float spacing = FIREFLY_SPACING;
    vec3 playerCell = floor(cameraPosition / spacing);

    // Check a 7x3x7 grid of cells around player (horizontal range, limited vertical)
    for (int iz = -3; iz <= 3; iz++) {
    for (int iy = -1; iy <= 1; iy++) {
    for (int ix = -3; ix <= 3; ix++) {
        vec3 cell = (playerCell + vec3(ix, iy, iz)) * spacing;

        // Each cell has a chance to spawn a firefly
        float spawnRoll = ffHash(cell * 0.01 + 0.5);
        if (spawnRoll > FIREFLY_DENSITY) continue;

        float seed = ffHash(cell * 0.007);
        vec3 wpos  = getFireflyPos(cell, seed, t);

        // Only near ground — skip if too high above camera
        if (wpos.y - cameraPosition.y > 8.0) continue;
        if (wpos.y - cameraPosition.y < -4.0) continue;

        vec4 screen = worldToScreen(wpos);
        if (screen.w < 0.0) continue;
        if (screen.x < 0.0 || screen.x > 1.0 || screen.y < 0.0 || screen.y > 1.0) continue;

        // Depth test — hide if behind geometry
        float sceneDepth = texture(depthTex, screen.xy).r;
        if (screen.z > sceneDepth) continue;

        // Distance fade
        float dist = length(wpos - cameraPosition);
        if (dist > FIREFLY_SPACING * 4.5) continue;
        float distFade = smoothstep(FIREFLY_SPACING * 4.5, FIREFLY_SPACING * 1.5, dist);

        // Screen-space glow
        vec2 delta = (uv - screen.xy) * vec2(aspectRatio, 1.0);
        float d    = length(delta);

        // Core dot
        float core = smoothstep(0.003, 0.0, d);
        // Soft glow halo
        float glow = 1.0 / (d * 300.0 + 1.0) * 0.03;
        // Trail: smear in direction of motion (approximate with elongation)
        float trailAngle = t * ffHash(cell + 2.3) + ffHash(cell + 8.1) * 6.28;
        vec2  trailDir   = vec2(cos(trailAngle), sin(trailAngle));
        float trail      = 1.0 / (abs(dot(delta, trailDir)) * 400.0
                         + length(delta - dot(delta, trailDir) * trailDir) * 600.0 + 1.0) * 0.015;

        float totalBright = (core * 0.8 + glow + trail) * distFade * strength;

        // Firefly color: warm yellow-green, slight per-fly hue variation
        float hue = ffHash(cell + 4.4);
        vec3 ffColor = mix(
            vec3(0.6, 1.0, 0.2), // yellow-green
            vec3(1.0, 0.9, 0.2), // warm yellow
            hue
        );

        // Flicker: slow smooth pulse
        float flicker = 0.7 + 0.3 * sin(t * (ffHash(cell + 6.6) * 1.5 + 0.5) + ffHash(cell + 15.3) * 6.28);
        result += ffColor * totalBright * flicker;
    }}}

    return result;
}

#endif // FIREFLIES_GLSL

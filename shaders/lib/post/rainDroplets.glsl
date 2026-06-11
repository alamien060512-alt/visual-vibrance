// rain droplets

#ifndef RAIN_DROPLETS_GLSL
#define RAIN_DROPLETS_GLSL

float dHash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 dHash2(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

vec3 dropletLayer(vec2 uv, float time, float seed) {
    // Aspect-corrected cell grid — tall cells so drops have room to slide
    vec2 cellSize = vec2(
        DROPLET_GRID_SIZE / aspectRatio,
        DROPLET_GRID_SIZE * 2.5
    );

    vec2 cell  = floor(uv / cellSize);
    vec2 local = fract(uv / cellSize);

    vec3 result = vec3(0.0);

    for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
        vec2 nb   = cell + vec2(dx, dy);
        vec2 rnd  = dHash2(nb + seed * 7.3);
        float r1  = dHash(nb + seed * 3.1);
        float r2  = dHash(nb + seed * 11.7);
        float r3  = dHash(nb + seed * 17.3);

        float spawnOffset = r1 * 6.0;
        float cycleLen    = 4.0 + r2 * 3.0;
        float localTime   = mod(time * DROPLET_SPEED + spawnOffset, cycleLen + 1.5);

        // alive = sliding phase only
        if (localTime > cycleLen) continue;
        float fallT = localTime / cycleLen;

        // x position: fixed per drop
        float dropX = rnd.x * 0.6 + 0.2;
        // y: slides from ~0.9 to ~0.05 with slight wobble
        float dropY = mix(0.92, 0.05, fallT * fallT)
                    + sin(localTime * 4.0 + r3 * 6.28) * 0.015;

        vec2 dropPos = vec2(dropX, dropY);
        vec2 diff    = local - vec2(dx, dy) - dropPos;

        // Teardrop shape: narrow at top, slightly wider at bottom
        // stretch horizontally less than vertically
        float scaleX = 1.0 / (0.3 + fallT * 0.1); // narrow x
        float scaleY = 1.0 / (0.55 + fallT * 0.2); // taller y
        vec2  shaped = diff * vec2(scaleX, scaleY);
        float dist   = length(shaped);

        // Base size — much smaller than before
        float size = (0.018 + r3 * 0.012) * DROPLET_SIZE;

        if (dist > size * 2.5) continue;

        // Teardrop: pointy top, round bottom
        // shift center upward to make bottom rounder
        float tearDrop = length(diff * vec2(8.0, 5.0) + vec2(0.0, -0.002));
        float mask = smoothstep(size, size * 0.2, tearDrop);

        // Fade at end of life
        float fade  = smoothstep(cycleLen - 0.4, cycleLen, localTime);
        float alpha = mask * (1.0 - fade);

        // Refraction: push outward from drop center (convex lens)
        vec2 normal = normalize(diff + vec2(0.0001));
        result.xy  += normal * alpha * 0.006 * DROPLET_REFRACTION;
        result.z    = max(result.z, alpha);
    }}

    return result;
}

vec3 getRainDroplets(vec2 uv, sampler2D sceneTex) {
    vec3 scene = texture(sceneTex, uv).rgb;
    if (rainStrength < 0.01 || isEyeInWater != 0) return scene;

    float intensity = rainStrength * DROPLET_INTENSITY;
    float t = frameTimeCounter;

    vec3 l1 = dropletLayer(uv, t,        0.0);
    vec3 l2 = dropletLayer(uv, t * 0.6,  5.3);

    vec2  distort     = (l1.xy + l2.xy * 0.5) * intensity;
    float totalAlpha  = max(l1.z, l2.z) * intensity;

    vec2  distUV   = clamp(uv + distort, vec2(0.001), vec2(0.999));
    vec3  refracted = texture(sceneTex, distUV).rgb;
    vec3  dropColor = mix(refracted, vec3(0.75, 0.8, 0.85), 0.1);

    return mix(scene, dropColor, totalAlpha);
}

#endif

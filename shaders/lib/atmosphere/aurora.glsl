// aurora, stars, end galaxy

#ifndef AURORA_GLSL
#define AURORA_GLSL

// hashing

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float hash13(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float smoothNoise(vec2 uv) {
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i + vec2(0,0)), hash12(i + vec2(1,0)), u.x),
        mix(hash12(i + vec2(0,1)), hash12(i + vec2(1,1)), u.x),
        u.y
    );
}

float fbm(vec2 uv) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * smoothNoise(uv);
        uv *= 2.1;
        a *= 0.5;
    }
    return v;
}

// stars

float getStars(vec3 dir, float nightFactor) {
    if (nightFactor < 0.01) return 0.0;

    float horizonFade = smoothstep(-0.05, 0.15, dir.y);
    if (horizonFade < 0.001) return 0.0;

    // Scale direction into cell space
    float scale = STAR_DENSITY * 0.08; // tuned so density matches old setting
    vec3 scaled = dir * scale;

    vec3 cell = floor(scaled);
    vec3 local = fract(scaled);

    float brightness = 0.0;

    for (int dz = 0; dz <= 1; dz++) {
    for (int dy = 0; dy <= 1; dy++) {
    for (int dx = 0; dx <= 1; dx++) {
        vec3 nb = cell + vec3(dx, dy, dz);
        // Star position inside cell — jitter away from edges
        vec3 sp = vec3(
            hash13(nb),
            hash13(nb + 7.3),
            hash13(nb + 13.7)
        ) * 0.7 + 0.15;

        vec3 diff = local - vec3(dx, dy, dz) - sp;
        float dist = length(diff);

        float twinkle = 0.6 + 0.4 * sin(frameTimeCounter * (hash13(nb) * 2.0 + 0.5)
                                        + hash13(nb + 3.1) * 6.28);
        float size = (0.12 + hash13(nb) * 0.12) * twinkle;
        brightness += smoothstep(size, 0.0, dist) * (0.4 + hash13(nb + 5.5) * 0.6);
    }}}

    return brightness * horizonFade * nightFactor;
}

vec3 getStarColor(vec3 dir) {
    float scale = STAR_DENSITY * 0.08;
    vec3 cell = floor(dir * scale);
    float h = hash13(cell);
    return mix(vec3(0.7, 0.85, 1.0), vec3(1.0, 0.95, 0.75), h);
}

// aurora

float getSnowyBiomeFactor() {
    vec3 fc = pow(fogColor, vec3(2.2));
    float sat = max(fc.r, max(fc.g, fc.b)) - min(fc.r, min(fc.g, fc.b));
    float cold = fc.b - fc.r;
    return clamp01(smoothstep(0.04, 0.0, sat) + smoothstep(0.0, 0.03, cold));
}

vec3 getAurora(vec3 dir, float nightFactor) {
    float snowFactor = getSnowyBiomeFactor();
    float auroraStrength = snowFactor * nightFactor * AURORA_STRENGTH;
    if (auroraStrength < 0.001) return vec3(0.0);

    // Fade: only upper sky, never at horizon
    float elevFade = smoothstep(0.15, 0.5, dir.y);
    if (elevFade < 0.001) return vec3(0.0);

    float t = frameTimeCounter * 0.04;

    // Use only xz angle for curtain columns — avoids zenith pinch
    float longitude = atan(dir.z, dir.x); // -PI..PI but only used in sin/cos space

    // Convert to a smooth 2D space using sin/cos to avoid the atan seam
    vec2 horizDir = normalize(dir.xz + vec2(0.0001)); // safe normalize
    
    // Curtain UV: x = smooth longitude via 2D coords, y = elevation
    // Using the actual xz components avoids the atan discontinuity
    vec2 uv1 = vec2(horizDir.x * 3.0 + horizDir.y * 2.0 + t * 0.3,
                    dir.y * 2.0 + t * 0.08);
    vec2 uv2 = vec2(horizDir.y * 3.5 - horizDir.x * 2.5 - t * 0.2,
                    dir.y * 2.5 - t * 0.1);

    float curtain1 = fbm(uv1 * 2.0);
    float curtain2 = fbm(uv2 * 2.5 + 4.7);

    float band1 = pow(clamp01(curtain1 * 2.0 - 0.6), 2.0);
    float band2 = pow(clamp01(curtain2 * 2.0 - 0.5), 2.0);
    float curtains = band1 * 0.6 + band2 * 0.4;

    vec2 shimmerUV = vec2(horizDir.x * 6.0 + t * 1.5, horizDir.y * 6.0);
    float shimmer = smoothNoise(shimmerUV) * 0.4 + 0.6;

    float intensity = curtains * shimmer * elevFade;

    float colorShift = smoothstep(0.2, 0.7, dir.y) + fbm(uv1 * 3.0 + 2.3) * 0.3;
    vec3 auroraColor = mix(
        vec3(0.0, 0.9, 0.3),
        mix(
            vec3(0.0, 0.7, 0.6),
            vec3(0.3, 0.1, 0.8),
            smoothstep(0.5, 1.0, colorShift)
        ),
        smoothstep(0.0, 0.5, colorShift)
    );

    return auroraColor * intensity * auroraStrength * 0.8;
}

// end sky

vec3 getEndGalaxy(vec3 dir) {
    float tilt = 0.5;
    vec3 gdir = vec3(dir.x,
                     dir.y * cos(tilt) - dir.z * sin(tilt),
                     dir.y * sin(tilt) + dir.z * cos(tilt));

    // Galaxy band — use dot with a fixed axis instead of atan
    vec3 galaxyAxis = normalize(vec3(0.0, 0.0, 1.0));
    float band = 1.0 - abs(dot(gdir, galaxyAxis)) / (length(gdir) + 0.001);
    band = pow(clamp01(band * 1.5 - 0.2), 3.0);

    // Seamless nebula using 3D noise on the direction
    float t = frameTimeCounter * 0.005;
    vec3 nebulaP = gdir * 2.0 + vec3(t, 0.0, t * 0.5);
    // Approximate 3D fbm using two 2D slices
    float nebula  = fbm(vec2(hash13(floor(nebulaP * 4.0)),
                             hash13(floor(nebulaP * 4.0 + 7.3))) * 4.0);
    float nebula2 = fbm(vec2(hash13(floor(nebulaP * 7.0 + 1.7)),
                             hash13(floor(nebulaP * 7.0 + 3.1))) * 4.0);

    vec3 nebulaColor = mix(
        vec3(0.05, 0.0, 0.15),
        mix(
            vec3(0.1, 0.05, 0.3),
            vec3(0.4, 0.2, 0.05),
            smoothstep(0.5, 0.8, nebula2)
        ),
        nebula
    );

    float galaxyBrightness = band * (0.4 + nebula * 0.6) * GALAXY_STRENGTH;
    vec3 galaxy = nebulaColor * galaxyBrightness;

    // Seamless End stars — 3D cell noise, no atan
    float scale = STAR_DENSITY * 0.12;
    vec3 scaled = dir * scale;
    vec3 cell = floor(scaled);
    vec3 local = fract(scaled);
    float stars = 0.0;
    vec3 starCol = vec3(0.0);

    for (int dz = 0; dz <= 1; dz++) {
    for (int dy = 0; dy <= 1; dy++) {
    for (int dx = 0; dx <= 1; dx++) {
        vec3 nb = cell + vec3(dx, dy, dz);
        vec3 sp = vec3(
            hash13(nb),
            hash13(nb + 7.3),
            hash13(nb + 13.7)
        ) * 0.7 + 0.15;

        float dist = length(local - vec3(dx, dy, dz) - sp);
        float twinkle = 0.7 + 0.3 * sin(frameTimeCounter * (hash13(nb) + 0.3) * 3.0);
        float size = (0.1 + hash13(nb) * 0.1) * twinkle;
        float b = smoothstep(size, 0.0, dist) * (0.4 + hash13(nb + 3.1) * 0.6);

        float hue = hash13(nb + 1.1);
        vec3 col = hue < 0.33
            ? vec3(0.4, 1.0, 0.9)
            : hue < 0.66
                ? vec3(0.8, 0.4, 1.0)
                : vec3(1.0, 0.7, 0.8);
        stars += b;
        starCol += b * col;
    }}}

    if (stars > 0.001) starCol /= stars;
    return galaxy + starCol * stars * END_STAR_BRIGHTNESS;
}

#endif // AURORA_GLSL

// ============================================================
//  STAR FLIGHT — v1.0
//  Created by RBambey
//  Fly through a star field with nebulae. Audio reactive.
// ============================================================

// ---- Camera rotation matrices ----
mat3 rotX(float a) {
    float c = cos(a), s = sin(a);
    return mat3(1.0,0.0,0.0,  0.0,c,-s,  0.0,s,c);
}
mat3 rotY(float a) {
    float c = cos(a), s = sin(a);
    return mat3(c,0.0,s,  0.0,1.0,0.0,  -s,0.0,c);
}
mat3 rotZ(float a) {
    float c = cos(a), s = sin(a);
    return mat3(c,-s,0.0,  s,c,0.0,  0.0,0.0,1.0);
}

// ---- Hash / noise ----
float hash1(float n)  { return fract(sin(n) * 43758.5453); }
float hash1(vec2 p)   { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash1(vec3 p)   { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

vec3 hash3(vec3 p) {
    return fract(sin(vec3(
        dot(p, vec3(127.1, 311.7,  74.7)),
        dot(p, vec3(269.5, 183.3, 246.1)),
        dot(p, vec3(113.5, 271.9, 124.6))
    )) * 43758.5453);
}

// Smooth 3-D value noise (trilinear)
float vnoise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = hash1(i + vec3(0,0,0));
    float n100 = hash1(i + vec3(1,0,0));
    float n010 = hash1(i + vec3(0,1,0));
    float n110 = hash1(i + vec3(1,1,0));
    float n001 = hash1(i + vec3(0,0,1));
    float n101 = hash1(i + vec3(1,0,1));
    float n011 = hash1(i + vec3(0,1,1));
    float n111 = hash1(i + vec3(1,1,1));
    return mix(mix(mix(n000,n100,f.x), mix(n010,n110,f.x), f.y),
               mix(mix(n001,n101,f.x), mix(n011,n111,f.x), f.y), f.z);
}

// 4-octave FBM
float fbm(vec3 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p  = p * 2.1 + vec3(31.4, 17.7, 43.1);
        a *= 0.5;
    }
    return v;
}

// ---- Background stars (infinite distance, spherical hash) ----
// Three density layers at different angular scales.
vec3 bgStars(vec3 rd, float density, float bassBoost) {
    vec3 result = vec3(0.0);
    vec2 angles = vec2(atan(rd.x, rd.z), asin(clamp(rd.y, -1.0, 1.0)));

    // Layer 1 — fine grain
    vec2 uv1 = angles * 90.0;
    float h1  = hash1(floor(uv1));
    float thr1 = 0.99 - density * 0.12;
    float m1  = smoothstep(thr1, 1.0, h1);
    vec3  c1  = mix(vec3(0.85, 0.90, 1.00), vec3(1.00, 0.92, 0.75), hash1(h1 * 7.3));
    result   += m1 * c1 * (0.6 + bassBoost * 0.5);

    // Layer 2 — medium
    vec2 uv2 = angles * 55.0 + vec2(17.3, 43.1);
    float h2  = hash1(floor(uv2));
    float thr2 = 0.985 - density * 0.10;
    float m2  = smoothstep(thr2, 1.0, h2);
    vec3  c2  = mix(vec3(0.95, 0.95, 1.00), vec3(0.75, 0.85, 1.00), hash1(h2 * 5.1));
    result   += m2 * c2 * 1.2 * (0.6 + bassBoost * 0.7);

    // Layer 3 — bright clusters
    vec2 uv3 = angles * 30.0 + vec2(-8.9, 22.4);
    float h3  = hash1(floor(uv3));
    float thr3 = 0.993 - density * 0.07;
    float m3  = smoothstep(thr3, 1.0, h3);
    vec3  c3  = mix(vec3(1.00, 1.00, 1.00), vec3(0.90, 0.70, 1.00), hash1(h3 * 9.7));
    result   += m3 * c3 * 2.5 * (0.7 + bassBoost * 1.0);

    return result;
}

// ---- 3-D foreground stars (fly through them) ----
vec3 closeStars(vec3 rd, vec3 ro, float density, float bassBoost) {
    vec3 result = vec3(0.0);
    float CELL  = 10.0;
    float thresh = 1.0 - density * 0.35;   // higher density → more cells have stars

    for (int i = 0; i < 20; i++) {
        float t      = (float(i) + 0.5) * CELL;
        vec3 sampleP = ro + rd * t;
        vec3 cellID  = floor(sampleP / CELL);

        float h = hash1(cellID);
        if (h > thresh) {
            vec3  h3      = hash3(cellID);
            vec3  starPos = (cellID + 0.2 + h3 * 0.6) * CELL;

            vec3  toStar = starPos - ro;
            float proj   = dot(toStar, rd);
            if (proj > 0.5) {
                float perpDist = length(toStar - proj * rd);
                float size     = 0.10 + h * 0.30;
                float bright   = smoothstep(size, 0.0, perpDist);
                float fade     = 1.0 - t / (CELL * 20.0);
                vec3  col      = mix(vec3(1.0, 1.0, 1.0), vec3(0.7, 0.85, 1.0), h3.x);
                result        += bright * fade * col * (1.5 + bassBoost * 1.5);
            }
        }
    }
    return result;
}

// ---- Nebula sampling at a world-space position ----
// Returns rgb color and accumulated density in .a
vec4 nebulaSample(vec3 p) {
    vec3  col     = vec3(0.0);
    float density = 0.0;

    // Cloud A — blue/purple (dominant, offset to upper-left-ish)
    float nA = fbm(p * 0.009 + vec3(0.0, 4.0, 8.0));
    float dA = max(0.0, nA - 0.44) * 2.5;
    col     += dA * mix(vec3(0.10, 0.28, 0.90), vec3(0.45, 0.08, 0.80),
                        clamp(nA * 1.8 - 0.7, 0.0, 1.0));
    density += dA;

    // Cloud B — red/orange (accent, offset to lower-right-ish)
    float nB = fbm(p * 0.011 + vec3(-18.0, -5.0, -14.0));
    float dB = max(0.0, nB - 0.46) * 2.0;
    col     += dB * mix(vec3(0.90, 0.38, 0.08), vec3(0.80, 0.12, 0.30),
                        clamp(nB * 2.0 - 0.9, 0.0, 1.0));
    density += dB;

    // Cloud C — magenta highlight
    float nC = fbm(p * 0.007 + vec3(12.0, 9.0, 30.0));
    float dC = max(0.0, nC - 0.48) * 1.5;
    col     += dC * vec3(0.65, 0.05, 0.55);
    density += dC;

    return vec4(col, density);
}

// ---- Volume-march nebulae ----
vec3 nebulaVolume(vec3 ro, vec3 rd, float amount) {
    if (amount < 0.01) return vec3(0.0);

    vec3  accColor = vec3(0.0);
    float accAlpha = 0.0;
    float stepSize = 55.0;

    for (int i = 0; i < 16; i++) {
        float t  = (float(i) + 0.5) * stepSize;
        vec3  p  = ro + rd * t;
        vec4  ns = nebulaSample(p);

        float d     = ns.w * amount;
        float alpha = 1.0 - exp(-d * stepSize * 0.018);
        float remain = 1.0 - accAlpha;

        accColor += ns.rgb / max(ns.w, 0.001) * alpha * remain;
        accAlpha += alpha * remain;

        if (accAlpha > 0.97) break;
    }

    return accColor * clamp(accAlpha, 0.0, 1.0);
}

// ---- Main render ----
vec4 renderMain() {

    vec3 ro = vec3(cam_x, cam_y, cam_z);

    // Full camera rotation: yaw then roll then pitch
    mat3 camRot = rotY(cam_yaw) * rotZ(cam_roll) * rotX(cam_pitch);

    vec2 uv = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd = normalize(camRot * vec3(uv.x, uv.y, 1.0));

    // ---- Bass pulse — expanding ring from screen center ----
    // syn_BassTime accumulates with bass energy, driving the ring outward.
    float screenDist  = length(_uv - 0.5) * 2.0;   // 0 = center, ~1.41 = corner
    float ringPhase   = screenDist * 9.0 - syn_BassTime * 9.0;
    float bassRipple  = pow(clamp(sin(ringPhase) * 0.5 + 0.5, 0.0, 1.0), 2.0);
    bassRipple       *= syn_BassLevel;

    float bassBoost   = bassRipple * 2.5 + syn_BassLevel * 0.3;

    // ---- Deep space background ----
    vec3 col = vec3(0.0, 0.008, 0.035);

    // Slight vignette of blue towards corners for depth
    float vign = 1.0 - smoothstep(0.5, 1.2, screenDist);
    col = mix(col, vec3(0.0, 0.003, 0.018), 1.0 - vign);

    // ---- Nebulae ----
    col += nebulaVolume(ro, rd, nebula_amount);

    // ---- Stars ----
    if (star_count > 0.01) {
        col += bgStars(rd, star_count, bassBoost);
        col += closeStars(rd, ro, star_count, bassBoost);
    }

    // ---- Bass center flash — forward-direction glow ----
    float centerGlow = exp(-screenDist * screenDist * 4.0) * syn_BassLevel;
    col += vec3(0.4, 0.6, 1.0) * centerGlow * 1.8;

    // Subtle tone-map to avoid harsh clipping
    col = col / (col + 0.6);
    col = pow(col, vec3(0.85));

    return vec4(col, 1.0);
}

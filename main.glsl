// ============================================================
//  STAR FLIGHT — v1.1
//  Created by RBambey
//  Fly through a star field with nebulae. Audio reactive.
// ============================================================

mat3 rotX(float a) { float c=cos(a),s=sin(a); return mat3(1,0,0, 0,c,-s, 0,s,c); }
mat3 rotY(float a) { float c=cos(a),s=sin(a); return mat3(c,0,s, 0,1,0, -s,0,c); }
mat3 rotZ(float a) { float c=cos(a),s=sin(a); return mat3(c,-s,0, s,c,0, 0,0,1); }

float hash1(float n) { return fract(sin(n) * 43758.5453); }
float hash1(vec2 p)  { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash1(vec3 p)  { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
vec3  hash3(vec3 p)  {
    return fract(sin(vec3(dot(p,vec3(127.1,311.7,74.7)),
                          dot(p,vec3(269.5,183.3,246.1)),
                          dot(p,vec3(113.5,271.9,124.6)))) * 43758.5453);
}

// Trilinear value noise
float vnoise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    f = f*f*(3.0-2.0*f);
    return mix(
        mix(mix(hash1(i),           hash1(i+vec3(1,0,0)), f.x),
            mix(hash1(i+vec3(0,1,0)),hash1(i+vec3(1,1,0)), f.x), f.y),
        mix(mix(hash1(i+vec3(0,0,1)),hash1(i+vec3(1,0,1)), f.x),
            mix(hash1(i+vec3(0,1,1)),hash1(i+vec3(1,1,1)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {  // 3-octave FBM
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { v += a*vnoise(p); p = p*2.1 + vec3(31.4,17.7,43.1); a *= 0.5; }
    return v;
}
float fbm4(vec3 p) {  // 4-octave FBM
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a*vnoise(p); p = p*2.1 + vec3(31.4,17.7,43.1); a *= 0.5; }
    return v;
}

// ---- Render one star at screen position sUV ----
// pixUV   : current pixel in aspect-corrected UV space  (same space as `uv`)
// sUV     : star's screen position
// h,h3    : hash values for size/color variation
// streak  : streak vector pointing from star tip toward screen center
// boost   : bass brightness boost
vec3 renderStar(vec2 pixUV, vec2 sUV, float h, vec3 h3, vec2 streak, float boost) {
    vec2 delta = pixUV - sUV;

    // Capsule distance (star tip → streak tail)
    float dist2D;
    float sLen = length(streak);
    if (sLen > 0.001) {
        vec2 sDir = streak / sLen;
        float t = clamp(dot(delta, sDir), 0.0, sLen);
        dist2D = length(delta - sDir * t);
    } else {
        dist2D = length(delta);
    }

    // Core + soft glow
    float sz    = 0.0025 + h3.z * 0.004;
    float core  = smoothstep(sz, 0.0, dist2D);
    float glow  = exp(-dist2D * (55.0 - h3.y * 25.0)) * 0.35;

    // 4-spike diffraction cross centred on star (not on streak)
    float r  = length(delta);
    float ag = atan(delta.y, delta.x);
    float spikes = pow(abs(cos(ag * 2.0)), 10.0) * exp(-r * (100.0 - h * 50.0)) * 0.25;

    float bright = (core + glow + spikes) * (1.0 + boost * 1.8);

    // Color: mostly white-blue; a few warm yellow-white
    vec3 col = mix(vec3(1.00, 1.00, 1.00), vec3(0.65, 0.82, 1.00), h3.x * 0.6);
    col = mix(col, vec3(1.00, 0.90, 0.72), step(0.88, h3.x) * (h3.x - 0.88) * 8.0);

    return col * bright;
}

// ---- Nebula ----
// Two clouds multiplied by a breakup mask for patchy, non-uniform look.
vec4 nebulaSample(vec3 p) {
    vec3  col     = vec3(0.0);
    float density = 0.0;

    // Cloud A: blue/purple
    float nA   = fbm4(p * 0.009 + vec3(0.0, 4.0, 8.0));
    float brkA = fbm3(p * 0.016 + vec3(3.1, 7.4, 2.2));  // breakup
    float dA   = pow(max(0.0, nA - 0.50), 2.0) * max(0.0, brkA - 0.38) * 10.0;
    col     += dA * mix(vec3(0.10, 0.28, 0.90), vec3(0.45, 0.08, 0.80),
                        clamp(nA * 2.0 - 1.0, 0.0, 1.0));
    density += dA;

    // Cloud B: red/orange
    float nB   = fbm4(p * 0.011 + vec3(-18.0, -5.0, -14.0));
    float brkB = fbm3(p * 0.019 + vec3(-2.1, 4.3, 8.5));
    float dB   = pow(max(0.0, nB - 0.52), 2.0) * max(0.0, brkB - 0.40) * 8.0;
    col     += dB * mix(vec3(0.90, 0.38, 0.08), vec3(0.80, 0.12, 0.30),
                        clamp(nB * 2.0 - 1.0, 0.0, 1.0));
    density += dB;

    // Cloud C: magenta wisp (sparse)
    float nC   = fbm4(p * 0.007 + vec3(12.0, 9.0, 30.0));
    float brkC = fbm3(p * 0.013 + vec3(5.5, -3.1, 1.8));
    float dC   = pow(max(0.0, nC - 0.54), 2.0) * max(0.0, brkC - 0.42) * 6.0;
    col     += dC * vec3(0.65, 0.05, 0.55);
    density += dC;

    return vec4(col, density);
}

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
        float rem   = 1.0 - accAlpha;
        if (ns.w > 0.001) accColor += (ns.rgb / ns.w) * alpha * rem;
        accAlpha += alpha * rem;
        if (accAlpha > 0.97) break;
    }
    return accColor * clamp(accAlpha, 0.0, 1.0);
}

// ============================================================
vec4 renderMain() {

    vec3 ro       = vec3(cam_x, cam_y, cam_z);
    mat3 camRot   = rotY(cam_yaw) * rotZ(cam_roll) * rotX(cam_pitch);
    mat3 camRotInv = transpose(camRot);   // inverse of orthonormal matrix

    vec2 uv = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd = normalize(camRot * vec3(uv.x, uv.y, 1.0));

    // Bass pulse: expanding ring from screen centre
    float screenDist = length(_uv - 0.5) * 2.0;
    float ringPhase  = screenDist * 9.0 - syn_BassTime * 9.0;
    float bassRipple = pow(clamp(sin(ringPhase) * 0.5 + 0.5, 0.0, 1.0), 2.0) * syn_BassLevel;
    float bassBoost  = bassRipple * 2.5 + syn_BassLevel * 0.3;

    // Streak grows with fly_speed; scaled by star's radial screen distance
    // so stars aimed straight at you don't streak, edge stars streak most.
    float streakScale = fly_speed * 0.00010;

    // Deep space background
    vec3 col = vec3(0.0, 0.008, 0.035);

    // ---- Nebulae ----
    col += nebulaVolume(ro, rd, nebula_amount);

    // ---- Stars — three world-space scales ----
    // All stars are placed in 3-D cells, projected to screen space,
    // rendered as round points with glow + diffraction spikes + speed streak.
    // camRotInv lets us transform world→camera space for the projection.

    if (star_count > 0.01) {

        // --- Scale A: close  (CELL=6, covers ~132 units) ---
        float CELL_A = 6.0;
        float thr_A  = 1.0 - star_count * 0.28;
        for (int i = 0; i < 22; i++) {
            float depth = (float(i) + 0.5) * CELL_A;
            vec3  P     = ro + rd * depth;
            vec3  cID   = floor(P / CELL_A);
            float h     = hash1(cID);
            if (h > thr_A) {
                vec3 h3      = hash3(cID);
                vec3 starPos = (cID + 0.15 + h3 * 0.7) * CELL_A;
                vec3 sc      = camRotInv * (starPos - ro);
                if (sc.z > 0.1) {
                    vec2 sUV = sc.xy / sc.z;
                    if (abs(sUV.x) < 2.2 && abs(sUV.y) < 1.4) {
                        float rad   = length(sUV);
                        vec2 streak = (rad > 0.005) ? -normalize(sUV) * streakScale * rad : vec2(0.0);
                        col += renderStar(uv, sUV, h, h3, streak, bassBoost);
                    }
                }
            }
        }

        // --- Scale B: medium (CELL=22, covers ~484 units) ---
        float CELL_B = 22.0;
        float thr_B  = 1.0 - star_count * 0.32;
        for (int i = 0; i < 22; i++) {
            float depth = (float(i) + 0.5) * CELL_B;
            vec3  P     = ro + rd * depth;
            vec3  cID   = floor(P / CELL_B);
            float h     = hash1(cID);
            if (h > thr_B) {
                vec3 h3      = hash3(cID);
                vec3 starPos = (cID + 0.15 + h3 * 0.7) * CELL_B;
                vec3 sc      = camRotInv * (starPos - ro);
                if (sc.z > 0.1) {
                    vec2 sUV = sc.xy / sc.z;
                    if (abs(sUV.x) < 2.2 && abs(sUV.y) < 1.4) {
                        float rad   = length(sUV);
                        vec2 streak = (rad > 0.005) ? -normalize(sUV) * streakScale * 0.55 * rad : vec2(0.0);
                        col += renderStar(uv, sUV, h, h3, streak, bassBoost);
                    }
                }
            }
        }

        // --- Scale C: distant (CELL=80, covers ~1440 units) ---
        float CELL_C = 80.0;
        float thr_C  = 1.0 - star_count * 0.38;
        for (int i = 0; i < 18; i++) {
            float depth = (float(i) + 0.5) * CELL_C;
            vec3  P     = ro + rd * depth;
            vec3  cID   = floor(P / CELL_C);
            float h     = hash1(cID);
            if (h > thr_C) {
                vec3 h3      = hash3(cID);
                vec3 starPos = (cID + 0.15 + h3 * 0.7) * CELL_C;
                vec3 sc      = camRotInv * (starPos - ro);
                if (sc.z > 0.1) {
                    vec2 sUV = sc.xy / sc.z;
                    if (abs(sUV.x) < 2.2 && abs(sUV.y) < 1.4) {
                        float rad   = length(sUV);
                        vec2 streak = (rad > 0.005) ? -normalize(sUV) * streakScale * 0.25 * rad : vec2(0.0);
                        col += renderStar(uv, sUV, h, h3, streak, bassBoost) * 0.7;
                    }
                }
            }
        }
    }

    // Bass centre flash
    float centerGlow = exp(-screenDist * screenDist * 4.0) * syn_BassLevel;
    col += vec3(0.4, 0.6, 1.0) * centerGlow * 1.8;

    // Tone-map
    col = col / (col + 0.6);
    col = pow(col, vec3(0.85));

    return vec4(col, 1.0);
}

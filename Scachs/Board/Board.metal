// The board: enamel fields held in metal wire, and pieces baked as normal + metal + alpha so they relight live.
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 tilt;
    float  time;
    float  headroom;
    float2 reflexOrigin;
    float  reflexT;
    float  warmth;
    float  tilePixels;
    float  reduceFlash;
    float2 pad;
};
struct TileState { float4 tint; float dot; float wrong; float pad0; float pad1; };
struct PieceInstance { float2 center; float scale; float kind; float side; float alpha; float lift; float pad; };

struct VOut { float4 position [[position]]; float2 uv; };
struct POut { float4 position [[position]]; float2 uv; float2 boardUV; float side; float alpha; float lift; };

constant float3 tileLight = float3(0.8388, 0.7913, 0.6724);   // #ece6d6
constant float3 tileDark  = float3(0.0252, 0.1590, 0.1119);   // #2c6f5e
constant float3 wireCol   = float3(0.3968, 0.2307, 0.0497);   // #a9843f
constant float3 tinCol    = float3(0.9216, 0.8796, 0.7913);   // #f6f1e6
constant float3 inkCol    = float3(0.0080, 0.0060, 0.0116);   // #16121c
constant float3 metalOnWhiteDark = float3(0.0437, 0.0232, 0.0091);   // #3b2a18
constant float3 metalOnWhiteLit  = float3(0.4621, 0.2232, 0.0497);   // #b5823f
constant float3 metalOnInkDark   = float3(0.2542, 0.1441, 0.0369);   // #8a6a36
constant float3 metalOnInkLit    = float3(0.8879, 0.6240, 0.2623);   // #f2cf8c
constant float3 gold             = float3(0.7991, 0.4851, 0.1500);   // #e7b96c

static inline float sstep(float a, float b, float x) { float t = clamp((x - a) / (b - a), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }
static inline float hash21(float2 p) { p = fract(p * float2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }

// A room seen in the glaze: a soft ceiling, a dark floor, one tall window. Tilting the phone moves the room.
static float3 env(float3 R, float2 tilt, float warmth) {
    float3 r = normalize(float3(R.xy + tilt, R.z));
    float3 sky = mix(float3(0.70, 0.72, 0.78), float3(0.86, 0.68, 0.48), warmth) * sstep(-0.4, 0.9, r.y) * 0.9;
    float3 floorC = float3(0.04, 0.04, 0.05);
    float wx = (r.x + 0.56) / 0.22, wy = (r.y - 0.66) / 0.30;   // off the board at rest; tilting brings it in
    float d = max(abs(wx), abs(wy));
    float3 windowC = (1.0 - sstep(0.45, 1.0, d)) * mix(float3(1.0, 0.97, 0.92), float3(1.0, 0.80, 0.56), warmth);
    return floorC + sky + windowC * 5.5;
}

static inline float3 tonemap(float3 c, float headroom) {
    c = max(c, 0.0);
    return min(c * (1.0 + c / 9.0) / (1.0 + c * 0.22), headroom);
}

vertex VOut tileVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    VOut o; o.position = float4(p * 2.0 - 1.0, 0, 1); o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

// Quatrefoil painted in copper on the dark squares. It only exists when light catches it.
static float quatrefoil(float2 u) {
    float2 m = (u - 0.5) * 2.0;
    float r = 0.36;
    float a = abs(length(m - float2(r, 0)) - r), b = abs(length(m + float2(r, 0)) - r);
    float c = abs(length(m - float2(0, r)) - r), e = abs(length(m + float2(0, r)) - r);
    float q = min(min(a, b), min(c, e));
    float outside = step(0.30, length(m));
    return (1.0 - sstep(0.012, 0.03, q)) * outside;
}

fragment float4 tileFragment(VOut in [[stage_in]], constant Uniforms &U [[buffer(0)]], constant TileState *T [[buffer(1)]]) {
    float2 p = in.uv * 8.0;
    float2 cell = min(floor(p), float2(7.0));
    float2 u = p - cell;
    int ix = int(cell.x), iy = int(cell.y);
    bool dark = ((ix + iy) & 1) == 1;
    float tone = hash21(cell + 3.1);
    float2 tt = (float2(hash21(cell + 7.7), hash21(cell + 11.3)) - 0.5) * 0.022;
    float3 n = normalize(float3(tt, 1.0));
    float3 v = normalize(float3((in.uv.x - 0.5) * 0.7, -(in.uv.y - 0.5) * 0.7, 1.0));
    float3 R = reflect(-v, n);
    float3 E = env(R, U.tilt, U.warmth);
    float F = 0.04 + 0.96 * pow(1.0 - saturate(dot(n, v)), 5.0);
    float3 alb = dark ? tileDark * (1.0 + (tone - 0.5) * 0.12) : tileLight * (1.0 + (tone - 0.5) * 0.03);
    float3 col = alb * 0.94 + E * F * 0.75;

    constant TileState &S = T[iy * 8 + ix];
    col = mix(col, S.tint.rgb, S.tint.a);

    // The wave of light that runs out from the square of a solved move.
    float band = 0.0, wake = 0.0;
    if (U.reflexT >= 0.0) {
        float d = distance(in.uv, U.reflexOrigin);
        float front = U.reflexT * 1.15;
        band = exp(-pow((d - front) / 0.13, 2.0)) * sstep(1.9, 0.9, U.reflexT);
        wake = step(d, front) * exp(-max(U.reflexT - d / 1.15, 0.0) * 2.6);
    }
    float sheen = max(dot(E, float3(0.333)) * 0.55 - 0.32, 0.0);
    if (dark) {
        float motif = quatrefoil(u);
        float3 lustre = mix(float3(0.80, 0.40, 0.12), float3(0.95, 0.72, 0.36), saturate(R.x * 0.8 + U.tilt.x + 0.5));
        col += motif * lustre * (sheen * 1.6 + band * 2.6 + wake * 1.1 + 0.004);
    }
    col += gold * band * (dark ? 0.55 : 0.22) * (1.0 - U.reduceFlash * 0.7);

    // Legal moves: a bead of gold, or a ring of wire around what can be captured.
    if (S.dot > 1.5) {
        float d = length(u - 0.5);
        float ring = 1.0 - sstep(0.018, 0.03, abs(d - 0.455));
        col = mix(col, gold * 1.05, ring);
    } else if (S.dot > 0.5) {
        float d = length(u - 0.5);
        float bead = 1.0 - sstep(0.122, 0.135, d);
        float rim = sstep(0.09, 0.128, d);
        float3 nb = normalize(float3(u - 0.5, 0.18));
        float spec = pow(saturate(dot(nb, normalize(float3(-0.42, 0.7, 0.66)))), 24.0);
        col = mix(col, gold * (0.82 + 0.3 * rim) + spec * 1.2, bead);
    }
    col += float3(0.9, 0.08, 0.04) * S.wrong * (dark ? 0.55 : 0.32);

    // Wire between the squares.
    float edge = min(min(u.x, 1.0 - u.x), min(u.y, 1.0 - u.y));
    float w = 1.25 / U.tilePixels;
    float wm = 1.0 - sstep(w * 0.6, w * 1.2, edge);
    float3 wc = wireCol * clamp(0.7 + dot(E, float3(0.333)) * 0.55 + band * 3.0, 0.0, 3.2);
    col = mix(col, wc, wm);

    return float4(tonemap(col, U.headroom), 1.0);
}

vertex POut pieceVertex(uint vid [[vertex_id]], uint iid [[instance_id]], constant PieceInstance *I [[buffer(0)]], constant Uniforms &U [[buffer(1)]]) {
    constant PieceInstance &P = I[iid];
    float2 q = float2(vid & 1, (vid >> 1) & 1);        // 0..1, y down
    float size = 1.04 * P.scale;
    float2 b = P.center + (q - 0.5) * size + float2(0, -0.015);
    POut o;
    o.position = float4(b.x / 4.0 - 1.0, 1.0 - b.y / 4.0, 0, 1);
    o.uv = float2((P.kind + q.x) / 6.0, q.y);
    o.boardUV = b / 8.0;
    o.side = P.side; o.alpha = P.alpha; o.lift = P.lift;
    return o;
}

fragment float4 pieceFragment(POut in [[stage_in]], constant Uniforms &U [[buffer(0)]], texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float4 t = atlas.sample(s, in.uv, bias(-0.3));
    float a = t.a * in.alpha;
    if (a < 0.002) discard_fragment();
    float2 nxy = t.rg * 2.0 - 1.0;
    float3 n = float3(nxy, sqrt(saturate(1.0 - dot(nxy, nxy))));
    float3 v = normalize(float3((in.boardUV.x - 0.5) * 0.18, -(in.boardUV.y - 0.5) * 0.18, 1.0));
    float3 R = reflect(-v, n);
    float3 L = normalize(float3(-0.42 + U.tilt.x * 0.6, 0.70 + U.tilt.y * 0.6, 0.66));
    float wrap = saturate((dot(n, L) + 0.4) / 1.4);
    float F = 0.045 + 0.955 * pow(1.0 - saturate(n.z), 5.0);
    float3 E = env(R, U.tilt, U.warmth);
    float3 Ec = min(E, 5.0);
    float m = saturate(t.b);
    float3 en, metalDark, metalLit;
    if (in.side < 0.5) {
        en = tinCol * (0.70 + 0.36 * wrap) * (1.0 - F) + Ec * F * 0.9;
        metalDark = metalOnWhiteDark; metalLit = metalOnWhiteLit;
    } else {
        en = inkCol * (0.80 + 0.5 * wrap) * (1.0 - F) + Ec * (F * 1.05 + 0.012);
        metalDark = metalOnInkDark; metalLit = metalOnInkLit;
    }
    float sparkle = saturate(dot(E, float3(0.333)) * 0.55 + wrap * 0.35);
    float3 metal = mix(metalDark, metalLit, saturate(sparkle)) * (1.0 + max(sparkle - 0.8, 0.0) * 3.0);
    float3 col = mix(en, metal, m);
    col = tonemap(col, U.headroom);
    return float4(col * a, a);
}

vertex POut shadowVertex(uint vid [[vertex_id]], uint iid [[instance_id]], constant PieceInstance *I [[buffer(0)]], constant Uniforms &U [[buffer(1)]]) {
    constant PieceInstance &P = I[iid];
    float2 q = float2(vid & 1, (vid >> 1) & 1);
    float size = 1.04 * P.scale * (1.0 + P.lift * 0.05);
    float2 off = float2(0.018 - U.tilt.x * 0.03, 0.024 + U.tilt.y * 0.03) * (1.0 + P.lift * 4.0);
    float2 b = P.center + (q - 0.5) * size + float2(0, -0.015) + off;
    POut o;
    o.position = float4(b.x / 4.0 - 1.0, 1.0 - b.y / 4.0, 0, 1);
    o.uv = float2((P.kind + q.x) / 6.0, q.y);
    o.boardUV = b / 8.0;
    o.side = P.side; o.alpha = P.alpha; o.lift = P.lift;
    return o;
}

fragment float4 shadowFragment(POut in [[stage_in]], texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float a = atlas.sample(s, in.uv, level(3.2 + in.lift * 1.2)).a * in.alpha * (0.42 - in.lift * 0.12);
    return float4(0.0, 0.0, 0.0, a);
}

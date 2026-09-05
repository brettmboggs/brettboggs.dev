#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The one living thing in the app.
//
// A soft body of warm light whose radius follows `breath` (0 empty, 1 full)
// and swells a little with `energy` (the audio meter). The surface is domain-
// warped value noise so it never sits still and never repeats. `rim` puts a
// glow around the edge of the screen that thickens on the inhale, which is
// the part that reads as the whole phone breathing.

static float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float2x2 rotate = float2x2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 4; i++) {
        value += amplitude * vnoise(p);
        p = rotate * p * 2.0 + 17.0;
        amplitude *= 0.5;
    }
    return value;
}

[[ stitchable ]] half4 nightjarOrb(float2 position, half4 color,
                                    float2 size, float time, float breath,
                                    float energy, float intensity, float rim,
                                    float centerY)
{
    float2 uv = position / size;
    float2 p = (position - float2(size.x * 0.5, size.y * centerY)) / size.y;
    float d = length(p);

    float t = time * 0.045;
    float2 q = float2(fbm(p * 2.0 + t), fbm(p * 2.0 - t * 0.7 + 3.7));
    float n = fbm(p * 2.6 + q * 0.7 + t * 0.4);

    float radius = 0.13 + breath * 0.075 + energy * 0.03;
    float edge = d - radius + (n - 0.5) * 0.08;
    float core = smoothstep(0.05, -0.09, edge);
    float halo = exp(-max(edge, 0.0) * 6.0) * (0.42 + breath * 0.25 + energy * 0.3);

    float3 ember = float3(0.89, 0.60, 0.29);
    float3 rose  = float3(0.80, 0.47, 0.44);
    float3 dusk  = float3(0.37, 0.39, 0.53);
    float3 cream = float3(0.98, 0.91, 0.80);

    float band = fbm(p * 3.0 - q * 0.8 + t * 0.6);
    float3 body = mix(ember, rose, smoothstep(0.30, 0.70, band));
    body = mix(body, dusk, smoothstep(0.55, 0.85, band) * 0.55);
    body = mix(body, cream, core * core * (0.25 + breath * 0.35));

    float2 b = min(uv, 1.0 - uv);
    float border = min(b.x, b.y);
    float rimGlow = exp(-border * (34.0 - breath * 16.0)) * rim * (0.35 + breath * 0.65);
    float3 rimColor = mix(rose, ember, fbm(uv * 3.0 + t * 0.8));

    float3 ground = float3(0.051, 0.043, 0.035);
    float3 out = ground;
    out += body * (core * 0.9 + halo) * intensity;
    out += rimColor * rimGlow;
    return half4(half3(out), 1.0h);
}

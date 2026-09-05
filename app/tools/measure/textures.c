// A faithful C port of Nightjar's synthesised textures, for measurement only.
//
// There is no Swift toolchain on Linux with AVFoundation, so this mirrors
// Audio/DSP.swift and the Texture subclasses closely enough to render each
// sound at its catalog defaults and report level, peak and brightness. The
// output drives the `trim` values in Model/SoundCatalog.swift so that every
// slider means the same loudness.
//
//   cc -O2 -o textures textures.c -lm && ./textures 30
//
// Keep this in step with the Swift when a texture changes. It is not the
// engine, it is a ruler.

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static float SR = 48000.0f;
#define PI 3.14159265358979f

static inline float clampf_(float x, float lo, float hi) { return x < lo ? lo : (x > hi ? hi : x); }
static inline float lerpf_(float a, float b, float t) { return a + (b - a) * t; }
static inline float perceptual(float x) { float c = clampf_(x, 0, 1); return c * c * c * 0.7f + c * 0.3f * c; }

// ---------------------------------------------------------------- random
typedef struct { uint32_t s; } Rng;
static Rng rng_make(uint32_t seed) { Rng r; r.s = seed == 0 ? 0x9E3779B9u : seed; return r; }
static inline uint32_t rng_next(Rng *r) { uint32_t s = r->s; s ^= s << 13; s ^= s >> 17; s ^= s << 5; r->s = s; return s; }
static inline float rng_uniform(Rng *r) { return (float)(rng_next(r) >> 8) * (1.0f / 16777216.0f); }
static inline float rng_bipolar(Rng *r) { return rng_uniform(r) * 2.0f - 1.0f; }

// ---------------------------------------------------------------- filters
typedef struct { float b0, b1, b2, b3, b4, b5, b6; } Pink;
static inline float pink(Pink *p, float w) {
    p->b0 = 0.99886f * p->b0 + w * 0.0555179f;
    p->b1 = 0.99332f * p->b1 + w * 0.0750759f;
    p->b2 = 0.96900f * p->b2 + w * 0.1538520f;
    p->b3 = 0.86650f * p->b3 + w * 0.3104856f;
    p->b4 = 0.55000f * p->b4 + w * 0.5329522f;
    p->b5 = -0.7616f * p->b5 - w * 0.0168980f;
    float out = p->b0 + p->b1 + p->b2 + p->b3 + p->b4 + p->b5 + p->b6 + w * 0.5362f;
    p->b6 = w * 0.115926f;
    return out * 0.18f;
}

typedef struct { float z; } Brown;
static inline float brown(Brown *b, float w) { b->z = (b->z + 0.02f * w) / 1.02f; return clampf_(b->z * 3.5f, -1, 1); }

typedef struct { float a, z; } OnePole;
static void op_cutoff(OnePole *o, float hz, float sr) { float f = clampf_(hz, 0.0001f, sr * 0.49f); o->a = clampf_(1 - expf(-2 * PI * f / sr), 0, 1); }
static void op_tc(OnePole *o, float sec, float sr) { float t = fmaxf(sec, 0.0001f); o->a = clampf_(1 - expf(-1 / (t * sr)), 0, 1); }
static inline float op(OnePole *o, float x) { o->z += o->a * (x - o->z); return o->z; }

typedef struct { float b0, b1, b2, a1, a2, z1, z2; } Biquad;
static void bq_init(Biquad *q) { memset(q, 0, sizeof *q); q->b0 = 1; }
static inline float bq(Biquad *q, float x) {
    float y = q->b0 * x + q->z1;
    q->z1 = q->b1 * x - q->a1 * y + q->z2;
    q->z2 = q->b2 * x - q->a2 * y;
    if (y > -1e-25f && y < 1e-25f) { q->z1 = 0; q->z2 = 0; }
    return y;
}
static void bq_reset(Biquad *q) { q->z1 = q->z2 = 0; }
static void bq_norm(Biquad *q, float nb0, float nb1, float nb2, float na0, float na1, float na2) {
    float inv = 1 / na0; q->b0 = nb0 * inv; q->b1 = nb1 * inv; q->b2 = nb2 * inv; q->a1 = na1 * inv; q->a2 = na2 * inv;
}
static float omega(float hz, float sr) { return 2 * PI * clampf_(hz, 10, sr * 0.47f) / sr; }
static void bq_lowpass(Biquad *q, float hz, float Q, float sr) { float w = omega(hz, sr), cw = cosf(w), al = sinf(w) / (2 * fmaxf(Q, 0.05f)); bq_norm(q, (1 - cw) / 2, 1 - cw, (1 - cw) / 2, 1 + al, -2 * cw, 1 - al); }
static void bq_highpass(Biquad *q, float hz, float Q, float sr) { float w = omega(hz, sr), cw = cosf(w), al = sinf(w) / (2 * fmaxf(Q, 0.05f)); bq_norm(q, (1 + cw) / 2, -(1 + cw), (1 + cw) / 2, 1 + al, -2 * cw, 1 - al); }
static void bq_bandpass(Biquad *q, float hz, float Q, float sr) { float w = omega(hz, sr), cw = cosf(w), al = sinf(w) / (2 * fmaxf(Q, 0.05f)); bq_norm(q, al, 0, -al, 1 + al, -2 * cw, 1 - al); }
static void bq_peak(Biquad *q, float hz, float Q, float db, float sr) { float a = powf(10, db / 40), w = omega(hz, sr), cw = cosf(w), al = sinf(w) / (2 * fmaxf(Q, 0.05f)); bq_norm(q, 1 + al * a, -2 * cw, 1 - al * a, 1 + al / a, -2 * cw, 1 - al / a); }
static void bq_lowshelf(Biquad *q, float hz, float db, float sr) {
    float a = powf(10, db / 40), w = omega(hz, sr), cw = cosf(w), sw = sinf(w);
    float al = sw / 2 * sqrtf((a + 1 / a) * (1 / 0.9f - 1) + 2), t = 2 * sqrtf(a) * al;
    bq_norm(q, a * ((a + 1) - (a - 1) * cw + t), 2 * a * ((a - 1) - (a + 1) * cw), a * ((a + 1) - (a - 1) * cw - t),
            (a + 1) + (a - 1) * cw + t, -2 * ((a - 1) + (a + 1) * cw), (a + 1) + (a - 1) * cw - t);
}
static void bq_highshelf(Biquad *q, float hz, float db, float sr) {
    float a = powf(10, db / 40), w = omega(hz, sr), cw = cosf(w), sw = sinf(w);
    float al = sw / 2 * sqrtf((a + 1 / a) * (1 / 0.9f - 1) + 2), t = 2 * sqrtf(a) * al;
    bq_norm(q, a * ((a + 1) + (a - 1) * cw + t), -2 * a * ((a - 1) + (a + 1) * cw), a * ((a + 1) + (a - 1) * cw - t),
            (a + 1) - (a - 1) * cw + t, 2 * ((a - 1) - (a + 1) * cw), (a + 1) - (a - 1) * cw - t);
}

typedef struct { float target; OnePole s1, s2; int counter, period; Rng rng; } Drift;
static Drift drift_make(uint32_t seed) { Drift d; memset(&d, 0, sizeof d); d.s1.a = d.s2.a = 0.01f; d.period = 4800; d.rng = rng_make(seed); return d; }
static void drift_prepare(Drift *d, float hz, float sr) { d->period = (int)fmaxf(sr / fmaxf(hz, 0.01f), 32); op_tc(&d->s1, 1 / fmaxf(hz, 0.01f), sr); op_tc(&d->s2, 1 / fmaxf(hz, 0.01f), sr); }
static inline float drift(Drift *d) { if (++d->counter >= d->period) { d->counter = 0; d->target = rng_bipolar(&d->rng); } return op(&d->s2, op(&d->s1, d->target)); }

typedef struct { float phase, inc; } Phasor;
static void ph_freq(Phasor *p, float hz, float sr) { p->inc = hz / sr; }
static inline float ph_phase(Phasor *p) { p->phase += p->inc; if (p->phase >= 1) p->phase -= 1; return p->phase; }
static inline float ph_sine(Phasor *p) { return sinf(2 * PI * ph_phase(p)); }

// ---------------------------------------------------------------- grains
typedef struct { int active; float amp, peak; int attackRemaining; float attackStep, decay, phase, phaseInc, noiseAmount, pan; Biquad filter; } Grain;
typedef struct { Grain *g; int n; Rng rng; float sr; } Bank;
static Bank bank_make(int cap, float sr, uint32_t seed) { Bank b; b.n = cap < 1 ? 1 : cap; b.g = calloc(b.n, sizeof(Grain)); for (int i = 0; i < b.n; i++) bq_init(&b.g[i].filter); b.rng = rng_make(seed); b.sr = sr; return b; }
static void bank_trigger(Bank *b, float freq, float decaySec, float amp, float noise, float pan, float res, float attackSec) {
    int idx = -1; float quiet = 1e30f;
    for (int i = 0; i < b->n; i++) { if (!b->g[i].active) { idx = i; break; } if (b->g[i].amp < quiet) { quiet = b->g[i].amp; idx = i; } }
    if (idx < 0) return;
    Grain g; memset(&g, 0, sizeof g); bq_init(&g.filter);
    g.active = 1; g.peak = amp; g.decay = expf(-1 / (fmaxf(decaySec, 0.001f) * b->sr)); g.phase = 0; g.phaseInc = freq / b->sr;
    g.noiseAmount = noise; g.pan = clampf_(pan, 0, 1); bq_bandpass(&g.filter, freq, res, b->sr);
    int attack = (int)(fmaxf(attackSec, 0) * b->sr);
    if (attack > 1) { g.amp = 0; g.attackRemaining = attack; g.attackStep = amp / (float)attack; } else { g.amp = amp; g.attackRemaining = 0; }
    b->g[idx] = g;
}
static inline void bank_next(Bank *b, float *L, float *R) {
    float l = 0, r = 0;
    for (int i = 0; i < b->n; i++) {
        Grain *g = &b->g[i]; if (!g->active) continue;
        g->phase += g->phaseInc; if (g->phase >= 1) g->phase -= 1;
        float tone = sinf(2 * PI * g->phase), noise = rng_bipolar(&b->rng);
        float raw = lerpf_(tone, bq(&g->filter, noise), g->noiseAmount), v = raw * g->amp;
        if (g->attackRemaining > 0) { g->amp += g->attackStep; if (--g->attackRemaining == 0) g->amp = g->peak; }
        else { g->amp *= g->decay; if (g->amp < 0.0002f) { g->active = 0; bq_reset(&g->filter); } }
        l += v * (1 - g->pan); r += v * g->pan;
    }
    *L = l * 1.4f; *R = r * 1.4f;
}

// ---------------------------------------------------------------- textures
typedef struct Tex Tex;
struct Tex {
    const char *id; float tone, motion;
    void (*build)(Tex *); void (*configure)(Tex *); void (*next)(Tex *, float *, float *);
    void *st;
};
#define ST(T) T *s = (T *)t->st
#define TONE (t->tone)
#define MOTION (t->motion)

// --- Rain
typedef struct { int character; Rng rngL, rngR, dropRNG; Biquad bedHPL, bedHPR, bedLPL, bedLPR; Pink pinkL, pinkR; Drift surge; Bank grains;
    float dropProbability, dropLow, dropSpan, dropDecay, dropResonance, dropNoise, dropLevel, bedLevel, surgeDepth; } RainS;
static void rain_build(Tex *t) { ST(RainS); s->grains = bank_make(40, SR, 0x0FAB); drift_prepare(&s->surge, 0.09f, SR); }
static void rain_configure(Tex *t) { ST(RainS); float tone = TONE, motion = MOTION;
    if (s->character == 0) { bq_highpass(&s->bedHPL, 700 + tone * 700, 0.7f, SR); bq_highpass(&s->bedHPR, 720 + tone * 700, 0.7f, SR); bq_lowpass(&s->bedLPL, 2600 + tone * 6000, 0.6f, SR); bq_lowpass(&s->bedLPR, 2650 + tone * 6000, 0.6f, SR);
        s->dropProbability = (18 + motion * 150) / SR; s->dropLow = 1200 + tone * 1800; s->dropSpan = 1800 + tone * 2600; s->dropDecay = 0.004f + (1 - tone) * 0.006f; s->dropResonance = 3.5f; s->dropNoise = 0.82f; s->dropLevel = 0.22f; s->bedLevel = 0.5f; s->surgeDepth = 0.06f + motion * 0.08f; }
    else if (s->character == 1) { bq_highpass(&s->bedHPL, 180 + tone * 400, 0.7f, SR); bq_highpass(&s->bedHPR, 190 + tone * 400, 0.7f, SR); bq_lowpass(&s->bedLPL, 3200 + tone * 5200, 0.6f, SR); bq_lowpass(&s->bedLPR, 3250 + tone * 5200, 0.6f, SR);
        s->dropProbability = (90 + motion * 320) / SR; s->dropLow = 700 + tone * 1200; s->dropSpan = 1600 + tone * 2200; s->dropDecay = 0.003f + (1 - tone) * 0.005f; s->dropResonance = 3; s->dropNoise = 0.9f; s->dropLevel = 0.16f; s->bedLevel = 0.78f; s->surgeDepth = 0.10f + motion * 0.16f; }
    else { bq_highpass(&s->bedHPL, 400 + tone * 500, 0.7f, SR); bq_highpass(&s->bedHPR, 420 + tone * 500, 0.7f, SR); bq_lowpass(&s->bedLPL, 2200 + tone * 3800, 0.6f, SR); bq_lowpass(&s->bedLPR, 2250 + tone * 3800, 0.6f, SR);
        s->dropProbability = (30 + motion * 190) / SR; s->dropLow = 900 + tone * 2200; s->dropSpan = 2400 + tone * 3400; s->dropDecay = 0.012f + tone * 0.055f; s->dropResonance = 6 + tone * 16; s->dropNoise = 0.55f - tone * 0.35f; s->dropLevel = 0.30f; s->bedLevel = 0.34f; s->surgeDepth = 0.05f + motion * 0.09f; }
}
static void rain_next(Tex *t, float *L, float *R) { ST(RainS);
    float swell = 1 + drift(&s->surge) * s->surgeDepth;
    float l = pink(&s->pinkL, rng_bipolar(&s->rngL)), r = pink(&s->pinkR, rng_bipolar(&s->rngR));
    l = bq(&s->bedLPL, bq(&s->bedHPL, l)) * s->bedLevel * swell; r = bq(&s->bedLPR, bq(&s->bedHPR, r)) * s->bedLevel * swell;
    if (rng_uniform(&s->dropRNG) < s->dropProbability * swell) {
        float f = s->dropLow + rng_uniform(&s->dropRNG) * s->dropSpan;
        bank_trigger(&s->grains, f, s->dropDecay * (0.6f + rng_uniform(&s->dropRNG) * 0.9f), s->dropLevel * (0.35f + rng_uniform(&s->dropRNG) * 0.9f), s->dropNoise, rng_uniform(&s->dropRNG), s->dropResonance, s->character == 2 ? 0.0012f : 0.0002f);
    }
    float gl, gr; bank_next(&s->grains, &gl, &gr); *L = l + gl; *R = r + gr;
}
static Tex *rain_make(const char *id, int ch, float tone, float motion) { Tex *t = calloc(1, sizeof *t); RainS *s = calloc(1, sizeof *s); s->character = ch; s->rngL = rng_make(0x12345678); s->rngR = rng_make(0x87654321); s->dropRNG = rng_make(0xBEEF0001); s->surge = drift_make(0x51A1);
    bq_init(&s->bedHPL); bq_init(&s->bedHPR); bq_init(&s->bedLPL); bq_init(&s->bedLPR);
    t->id = id; t->tone = tone; t->motion = motion; t->build = rain_build; t->configure = rain_configure; t->next = rain_next; t->st = s; return t; }

// --- Storm (hosts a heavy rain)
typedef struct { Tex *rain; Rng rng, noiseL, noiseR; Brown brownL, brownR; Biquad rumL, rumR; OnePole attack, body; Drift roll; int gateSamples, countdown; float strikeLevel, strikePan, rumbleCutoff; int rainControl; } StormS;
static void storm_build(Tex *t) { ST(StormS); s->rain = rain_make("rain.heavy", 1, 0.4f, 0.45f); s->rain->build(s->rain); s->rain->configure(s->rain);
    op_tc(&s->attack, 0.28f, SR); op_tc(&s->body, 0.55f, SR); drift_prepare(&s->roll, 1.6f, SR); s->countdown = (int)(SR * 6); }
static void storm_configure(Tex *t) { ST(StormS); s->rain->tone = 0.35f + TONE * 0.25f; s->rain->motion = 0.4f; s->rain->configure(s->rain);
    s->rumbleCutoff = 90 + (1 - TONE) * 900; bq_lowpass(&s->rumL, s->rumbleCutoff, 0.7f, SR); bq_lowpass(&s->rumR, s->rumbleCutoff * 1.05f, 0.7f, SR); }
static void storm_next(Tex *t, float *L, float *R) { ST(StormS);
    if (--s->countdown <= 0) { float mean = 90 - MOTION * 78, jitter = 0.45f + rng_uniform(&s->rng) * 1.4f; s->countdown = (int)fmaxf(SR * mean * jitter, SR * 4); s->gateSamples = (int)(SR * (0.25f + rng_uniform(&s->rng) * 1.3f)); s->strikeLevel = 0.35f + rng_uniform(&s->rng) * 0.65f; s->strikePan = 0.25f + rng_uniform(&s->rng) * 0.5f; }
    float gate = 0; if (s->gateSamples > 0) { s->gateSamples--; gate = s->strikeLevel; }
    float env = op(&s->body, op(&s->attack, gate)), rolling = env * (1 + drift(&s->roll) * 0.45f);
    float tl = 0, tr = 0;
    if (rolling > 0.0008f) { float bl = brown(&s->brownL, rng_bipolar(&s->noiseL)), br = brown(&s->brownR, rng_bipolar(&s->noiseR)); tl = bq(&s->rumL, bl) * rolling * (1 - s->strikePan) * 2.4f; tr = bq(&s->rumR, br) * rolling * s->strikePan * 2.4f; }
    float rl, rr; s->rain->next(s->rain, &rl, &rr); *L = rl * 0.85f + tl; *R = rr * 0.85f + tr;
}
static Tex *storm_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); StormS *s = calloc(1, sizeof *s); s->rng = rng_make(0x7B0D0001); s->noiseL = rng_make(0xAA11); s->noiseR = rng_make(0xBB22); s->roll = drift_make(0x33CC); bq_init(&s->rumL); bq_init(&s->rumR);
    t->id = "storm"; t->tone = tone; t->motion = motion; t->build = storm_build; t->configure = storm_configure; t->next = storm_next; t->st = s; return t; }

// --- Ocean
typedef struct { Rng rngL, rngR, cycleRNG; Brown brownL, brownR; Pink pinkL, pinkR; Biquad bodyL, bodyR, foamL, foamR; OnePole envSmooth; float phase, cycleSamples, risePortion, cycleAmp, foamAmount; } OceanS;
static void ocean_newcycle(Tex *t) { ST(OceanS); float base = 7 + MOTION * 6, spread = 1 + MOTION * 4; s->cycleSamples = SR * (base + rng_uniform(&s->cycleRNG) * spread); s->risePortion = 0.26f + rng_uniform(&s->cycleRNG) * 0.16f; s->cycleAmp = 0.55f + rng_uniform(&s->cycleRNG) * 0.45f; }
static void ocean_build(Tex *t) { ST(OceanS); op_tc(&s->envSmooth, 0.05f, SR); ocean_newcycle(t); }
static void ocean_configure(Tex *t) { ST(OceanS); bq_lowpass(&s->bodyL, 320 + TONE * 900, 0.6f, SR); bq_lowpass(&s->bodyR, 330 + TONE * 900, 0.6f, SR); bq_highpass(&s->foamL, 1400 + TONE * 3200, 0.6f, SR); bq_highpass(&s->foamR, 1430 + TONE * 3200, 0.6f, SR); s->foamAmount = 0.18f + TONE * 0.55f; }
static void ocean_next(Tex *t, float *L, float *R) { ST(OceanS);
    s->phase += 1 / s->cycleSamples; if (s->phase >= 1) { s->phase -= 1; ocean_newcycle(t); }
    float raw = s->phase < s->risePortion ? s->phase / s->risePortion : 1 - (s->phase - s->risePortion) / (1 - s->risePortion);
    float shaped = raw * raw * (3 - 2 * raw), env = op(&s->envSmooth, shaped * s->cycleAmp);
    float bl = brown(&s->brownL, rng_bipolar(&s->rngL)), br = brown(&s->brownR, rng_bipolar(&s->rngR));
    float bodyL = bq(&s->bodyL, bl) * (0.30f + env * 0.85f), bodyR = bq(&s->bodyR, br) * (0.30f + env * 0.85f);
    float crest = env * env * env;
    float fl = bq(&s->foamL, pink(&s->pinkL, rng_bipolar(&s->rngL))) * crest * s->foamAmount * 1.6f, fr = bq(&s->foamR, pink(&s->pinkR, rng_bipolar(&s->rngR))) * crest * s->foamAmount * 1.6f;
    *L = bodyL + fl; *R = bodyR + fr;
}
static Tex *ocean_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); OceanS *s = calloc(1, sizeof *s); s->rngL = rng_make(0x0CEA); s->rngR = rng_make(0x0CEB); s->cycleRNG = rng_make(0x0CEC); s->cycleSamples = 48000 * 11; s->risePortion = 0.34f; s->cycleAmp = 1; s->foamAmount = 0.4f; bq_init(&s->bodyL); bq_init(&s->bodyR); bq_init(&s->foamL); bq_init(&s->foamR);
    t->id = "ocean"; t->tone = tone; t->motion = motion; t->build = ocean_build; t->configure = ocean_configure; t->next = ocean_next; t->st = s; return t; }

// --- Stream
typedef struct { Rng rngL, rngR, burbleRNG; Pink pinkL, pinkR; Biquad bpL, bpR, hissL, hissR; Bank grains; float burbleProbability, burbleLow, burbleSpan; } StreamS;
static void stream_build(Tex *t) { ST(StreamS); s->grains = bank_make(28, SR, 0x57AA); }
static void stream_configure(Tex *t) { ST(StreamS); float center = 900 + TONE * 2200; bq_bandpass(&s->bpL, center, 0.8f, SR); bq_bandpass(&s->bpR, center * 1.04f, 0.8f, SR); bq_highpass(&s->hissL, 3000 + TONE * 3000, 0.7f, SR); bq_highpass(&s->hissR, 3050 + TONE * 3000, 0.7f, SR); s->burbleProbability = (25 + MOTION * 190) / SR; s->burbleLow = 260 + TONE * 500; s->burbleSpan = 600 + TONE * 1400; }
static void stream_next(Tex *t, float *L, float *R) { ST(StreamS);
    float nl = pink(&s->pinkL, rng_bipolar(&s->rngL)), nr = pink(&s->pinkR, rng_bipolar(&s->rngR));
    float l = bq(&s->bpL, nl) * 1.5f + bq(&s->hissL, nl) * 0.30f, r = bq(&s->bpR, nr) * 1.5f + bq(&s->hissR, nr) * 0.30f;
    if (rng_uniform(&s->burbleRNG) < s->burbleProbability) bank_trigger(&s->grains, s->burbleLow + rng_uniform(&s->burbleRNG) * s->burbleSpan, 0.012f + rng_uniform(&s->burbleRNG) * 0.045f, 0.10f + rng_uniform(&s->burbleRNG) * 0.20f, 0.35f, rng_uniform(&s->burbleRNG), 9 + rng_uniform(&s->burbleRNG) * 12, 0);
    float gl, gr; bank_next(&s->grains, &gl, &gr); *L = (l + gl) * 0.55f; *R = (r + gr) * 0.55f;
}
static Tex *stream_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); StreamS *s = calloc(1, sizeof *s); s->rngL = rng_make(0x5711); s->rngR = rng_make(0x5722); s->burbleRNG = rng_make(0x5733); bq_init(&s->bpL); bq_init(&s->bpR); bq_init(&s->hissL); bq_init(&s->hissR);
    t->id = "stream"; t->tone = tone; t->motion = motion; t->build = stream_build; t->configure = stream_configure; t->next = stream_next; t->st = s; return t; }

// --- Wind
typedef struct { int pines; Rng rngL, rngR; Pink pinkL, pinkR; Biquad bpL, bpR, bp2L, bp2R, hissL, hissR; Drift centerDrift, gustDrift, center2Drift; int coefCounter; float centerBase, centerRange, resonance, gustDepth, hissLevel, secondLevel; } WindS;
static void wind_build(Tex *t) { ST(WindS); drift_prepare(&s->centerDrift, 0.16f, SR); drift_prepare(&s->center2Drift, 0.11f, SR); drift_prepare(&s->gustDrift, 0.07f, SR); }
static void wind_configure(Tex *t) { ST(WindS); float tone = TONE;
    if (!s->pines) { s->centerBase = 240 + tone * 700; s->centerRange = 140 + tone * 420; s->resonance = 1.1f + tone * 1.4f; s->hissLevel = 0.05f + tone * 0.14f; s->secondLevel = 0; }
    else { s->centerBase = 1100 + tone * 2600; s->centerRange = 500 + tone * 1500; s->resonance = 1.6f + tone * 2.6f; s->hissLevel = 0.10f + tone * 0.26f; s->secondLevel = 0.55f; }
    s->gustDepth = 0.20f + MOTION * 0.70f; bq_highpass(&s->hissL, 4000, 0.7f, SR); bq_highpass(&s->hissR, 4100, 0.7f, SR); }
static void wind_next(Tex *t, float *L, float *R) { ST(WindS);
    float wander = drift(&s->centerDrift), wander2 = drift(&s->center2Drift);
    if (--s->coefCounter <= 0) { s->coefCounter = 32; float center = clampf_(s->centerBase + wander * s->centerRange, 60, SR * 0.4f); bq_bandpass(&s->bpL, center, s->resonance, SR); bq_bandpass(&s->bpR, center * 1.06f, s->resonance, SR);
        if (s->secondLevel > 0) { float c2 = clampf_(s->centerBase * 2.1f + wander2 * s->centerRange, 200, SR * 0.42f); bq_bandpass(&s->bp2L, c2, s->resonance * 1.5f, SR); bq_bandpass(&s->bp2R, c2 * 1.07f, s->resonance * 1.5f, SR); } }
    float nl = pink(&s->pinkL, rng_bipolar(&s->rngL)), nr = pink(&s->pinkR, rng_bipolar(&s->rngR));
    float l = bq(&s->bpL, nl) * 2.2f, r = bq(&s->bpR, nr) * 2.2f;
    if (s->secondLevel > 0) { l += bq(&s->bp2L, nl) * 1.6f * s->secondLevel; r += bq(&s->bp2R, nr) * 1.6f * s->secondLevel; }
    l += bq(&s->hissL, nl) * s->hissLevel; r += bq(&s->hissR, nr) * s->hissLevel;
    float gust = 1 + drift(&s->gustDrift) * s->gustDepth, level = clampf_(gust, 0.15f, 2.2f) * 0.55f; *L = l * level; *R = r * level;
}
static Tex *wind_make(const char *id, int pines, float tone, float motion) { Tex *t = calloc(1, sizeof *t); WindS *s = calloc(1, sizeof *s); s->pines = pines; s->rngL = rng_make(pines ? 0x3001 : 0x2001); s->rngR = rng_make(pines ? 0x3002 : 0x2002); s->centerDrift = drift_make(0x1D01); s->gustDrift = drift_make(0x1D02); s->center2Drift = drift_make(0x1D03);
    bq_init(&s->bpL); bq_init(&s->bpR); bq_init(&s->bp2L); bq_init(&s->bp2R); bq_init(&s->hissL); bq_init(&s->hissR);
    t->id = id; t->tone = tone; t->motion = motion; t->build = wind_build; t->configure = wind_configure; t->next = wind_next; t->st = s; return t; }

// --- Fire
typedef struct { Rng rngL, rngR, crackRNG; Brown brownL, brownR; Biquad roarL, roarR; Drift burst; Bank grains; float crackleProbability, roarLevel; } FireS;
static void fire_build(Tex *t) { ST(FireS); s->grains = bank_make(24, SR, 0xF1BB); drift_prepare(&s->burst, 0.22f, SR); }
static void fire_configure(Tex *t) { ST(FireS); float cutoff = 180 + TONE * 520; bq_lowpass(&s->roarL, cutoff, 0.7f, SR); bq_lowpass(&s->roarR, cutoff * 1.06f, 0.7f, SR); s->roarLevel = 0.35f + TONE * 0.75f; s->crackleProbability = (6 + MOTION * 70) / SR; }
static void fire_next(Tex *t, float *L, float *R) { ST(FireS);
    float bl = brown(&s->brownL, rng_bipolar(&s->rngL)), br = brown(&s->brownR, rng_bipolar(&s->rngR));
    float l = bq(&s->roarL, bl) * s->roarLevel * 1.5f, r = bq(&s->roarR, br) * s->roarLevel * 1.5f;
    float burst = 1 + drift(&s->burst) * 0.85f;
    if (rng_uniform(&s->crackRNG) < s->crackleProbability * fmaxf(burst, 0.1f)) { int big = rng_uniform(&s->crackRNG) < 0.08f;
        bank_trigger(&s->grains, big ? 260 + rng_uniform(&s->crackRNG) * 700 : 900 + rng_uniform(&s->crackRNG) * 5200, big ? 0.03f + rng_uniform(&s->crackRNG) * 0.07f : 0.002f + rng_uniform(&s->crackRNG) * 0.014f, big ? 0.22f + rng_uniform(&s->crackRNG) * 0.16f : 0.06f + rng_uniform(&s->crackRNG) * 0.22f, 0.78f, 0.15f + rng_uniform(&s->crackRNG) * 0.7f, 2.5f + rng_uniform(&s->crackRNG) * 6, big ? 0.004f : 0.0004f); }
    float gl, gr; bank_next(&s->grains, &gl, &gr); *L = l + gl; *R = r + gr;
}
static Tex *fire_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); FireS *s = calloc(1, sizeof *s); s->rngL = rng_make(0xF11E); s->rngR = rng_make(0xF12E); s->crackRNG = rng_make(0xF13E); s->burst = drift_make(0xF1AA); bq_init(&s->roarL); bq_init(&s->roarR);
    t->id = "fire"; t->tone = tone; t->motion = motion; t->build = fire_build; t->configure = fire_configure; t->next = fire_next; t->st = s; return t; }

// --- Crickets
typedef struct { int countdown, pulsesLeft, pulseSamples, gapSamples, inPulse; float phase, frequency, pan, amp; } Insect;
typedef struct { Insect in[7]; Rng rng, airL, airR; Pink pinkL, pinkR; Biquad airLPL, airLPR; OnePole env[7]; int activeCount; float baseFrequency; } CricketS;
static void cricket_build(Tex *t) { ST(CricketS); for (int i = 0; i < 7; i++) { s->in[i].countdown = (int)(rng_uniform(&s->rng) * SR * 3); op_tc(&s->env[i], 0.004f, SR); } bq_lowpass(&s->airLPL, 900, 0.6f, SR); bq_lowpass(&s->airLPR, 920, 0.6f, SR); }
static void cricket_configure(Tex *t) { ST(CricketS); s->baseFrequency = 3400 + TONE * 2800; s->activeCount = 2 + (int)(MOTION * 5); }
static void cricket_next(Tex *t, float *L, float *R) { ST(CricketS); float left = 0, right = 0; int n = s->activeCount < 7 ? s->activeCount : 7;
    for (int i = 0; i < n; i++) { Insect *c = &s->in[i];
        if (c->pulsesLeft <= 0) { if (--c->countdown <= 0) { c->pulsesLeft = 3 + (int)(rng_uniform(&s->rng) * 3); c->pulseSamples = (int)(SR * (0.012f + rng_uniform(&s->rng) * 0.014f)); c->gapSamples = (int)(SR * (0.020f + rng_uniform(&s->rng) * 0.030f)); c->frequency = s->baseFrequency * (0.86f + rng_uniform(&s->rng) * 0.30f); c->pan = rng_uniform(&s->rng); c->amp = 0.10f + rng_uniform(&s->rng) * 0.22f; c->inPulse = 1; c->countdown = c->pulseSamples; } }
        float target = 0;
        if (c->pulsesLeft > 0) { c->countdown--; if (c->inPulse) { target = 1; if (c->countdown <= 0) { c->inPulse = 0; c->countdown = c->gapSamples; c->pulsesLeft--; if (c->pulsesLeft <= 0) c->countdown = (int)(SR * (0.8f + rng_uniform(&s->rng) * 3.2f)); } } else if (c->countdown <= 0) { c->inPulse = 1; c->countdown = c->pulseSamples; } }
        float env = op(&s->env[i], target);
        if (env > 0.0008f) { c->phase += c->frequency / SR; if (c->phase >= 1) c->phase -= 1; float p = c->phase; float v = (sinf(2 * PI * p) + 0.35f * sinf(4 * PI * p)) * env * c->amp; left += v * (1 - c->pan); right += v * c->pan; } }
    float al = bq(&s->airLPL, pink(&s->pinkL, rng_bipolar(&s->airL))) * 0.16f, ar = bq(&s->airLPR, pink(&s->pinkR, rng_bipolar(&s->airR))) * 0.16f; *L = left + al; *R = right + ar;
}
static Tex *cricket_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); CricketS *s = calloc(1, sizeof *s); s->rng = rng_make(0xC21C); s->airL = rng_make(0xC22C); s->airR = rng_make(0xC23C); s->activeCount = 4; s->baseFrequency = 4500; bq_init(&s->airLPL); bq_init(&s->airLPR); for (int i = 0; i < 7; i++) { s->in[i].frequency = 4500; s->in[i].pan = 0.5f; s->in[i].amp = 0.5f; s->env[i].a = 0.01f; }
    t->id = "crickets"; t->tone = tone; t->motion = motion; t->build = cricket_build; t->configure = cricket_configure; t->next = cricket_next; t->st = s; return t; }

// --- Room tone
typedef struct { Rng rngL, rngR; Brown brownL, brownR; Pink pinkL, pinkR; Biquad lpL, lpR, peakL, peakR, airL, airR; Drift drift; float airLevel, driftDepth; } RoomS;
static void room_build(Tex *t) { ST(RoomS); drift_prepare(&s->drift, 0.05f, SR); }
static void room_configure(Tex *t) { ST(RoomS); bq_lowpass(&s->lpL, 180 + TONE * 260, 0.7f, SR); bq_lowpass(&s->lpR, 186 + TONE * 260, 0.7f, SR); bq_peak(&s->peakL, 62, 3, 7, SR); bq_peak(&s->peakR, 64, 3, 7, SR); bq_highpass(&s->airL, 5200, 0.7f, SR); bq_highpass(&s->airR, 5300, 0.7f, SR); s->airLevel = 0.03f + TONE * 0.13f; s->driftDepth = 0.05f + MOTION * 0.25f; }
static void room_next(Tex *t, float *L, float *R) { ST(RoomS); float wobble = 1 + drift(&s->drift) * s->driftDepth;
    float bl = brown(&s->brownL, rng_bipolar(&s->rngL)), br = brown(&s->brownR, rng_bipolar(&s->rngR));
    *L = bq(&s->peakL, bq(&s->lpL, bl)) * 1.7f * wobble + bq(&s->airL, pink(&s->pinkL, rng_bipolar(&s->rngL))) * s->airLevel;
    *R = bq(&s->peakR, bq(&s->lpR, br)) * 1.7f * wobble + bq(&s->airR, pink(&s->pinkR, rng_bipolar(&s->rngR))) * s->airLevel; }
static Tex *room_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); RoomS *s = calloc(1, sizeof *s); s->rngL = rng_make(0x900D); s->rngR = rng_make(0x900E); s->drift = drift_make(0x900F); bq_init(&s->lpL); bq_init(&s->lpR); bq_init(&s->peakL); bq_init(&s->peakR); bq_init(&s->airL); bq_init(&s->airR);
    t->id = "cabin"; t->tone = tone; t->motion = motion; t->build = room_build; t->configure = room_configure; t->next = room_next; t->st = s; return t; }

// --- Box fan
typedef struct { Rng rngL, rngR; Brown brownL, brownR; Pink pinkL, pinkR; Biquad lpL, lpR, hpL, hpR, motorL, motorR; Phasor blade, sweep; float bladeDepth, sweepDepth, motorLevel; } FanS;
static void fan_build(Tex *t) { ST(FanS); ph_freq(&s->blade, 21, SR); ph_freq(&s->sweep, 0.11f, SR); }
static void fan_configure(Tex *t) { ST(FanS); bq_lowpass(&s->lpL, 900 + TONE * 2600, 0.6f, SR); bq_lowpass(&s->lpR, 920 + TONE * 2600, 0.6f, SR); bq_highpass(&s->hpL, 60, 0.7f, SR); bq_highpass(&s->hpR, 62, 0.7f, SR); bq_peak(&s->motorL, 118, 5, 4 + TONE * 8, SR); bq_peak(&s->motorR, 120, 5, 4 + TONE * 8, SR); s->motorLevel = 0.25f + TONE * 0.5f; s->bladeDepth = 0.02f + MOTION * 0.16f; s->sweepDepth = MOTION > 0.55f ? (MOTION - 0.55f) * 1.1f : 0; }
static void fan_next(Tex *t, float *L, float *R) { ST(FanS);
    float bl = brown(&s->brownL, rng_bipolar(&s->rngL)) * 0.75f + pink(&s->pinkL, rng_bipolar(&s->rngL)) * 0.45f, br = brown(&s->brownR, rng_bipolar(&s->rngR)) * 0.75f + pink(&s->pinkR, rng_bipolar(&s->rngR)) * 0.45f;
    float l = bq(&s->motorL, bq(&s->hpL, bq(&s->lpL, bl))) * 1.5f * s->motorLevel, r = bq(&s->motorR, bq(&s->hpR, bq(&s->lpR, br))) * 1.5f * s->motorLevel;
    float chop = 1 + ph_sine(&s->blade) * s->bladeDepth; l *= chop; r *= chop;
    if (s->sweepDepth > 0) { float sv = ph_sine(&s->sweep), amount = s->sweepDepth * 0.5f; l *= 1 + sv * amount; r *= 1 - sv * amount; } else ph_phase(&s->sweep);
    *L = l; *R = r; }
static Tex *fan_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); FanS *s = calloc(1, sizeof *s); s->rngL = rng_make(0xFA01); s->rngR = rng_make(0xFA02); bq_init(&s->lpL); bq_init(&s->lpR); bq_init(&s->hpL); bq_init(&s->hpR); bq_init(&s->motorL); bq_init(&s->motorR);
    t->id = "fan"; t->tone = tone; t->motion = motion; t->build = fan_build; t->configure = fan_configure; t->next = fan_next; t->st = s; return t; }

// --- Airliner
typedef struct { Rng rngL, rngR; Brown brownL, brownR; Pink pinkL, pinkR; Biquad lpL, lpR, hullL, hullR, hissL, hissR; Drift turb, spectral; float hissLevel, turbDepth; } AirS;
static void air_build(Tex *t) { ST(AirS); drift_prepare(&s->turb, 0.06f, SR); drift_prepare(&s->spectral, 0.03f, SR); }
static void air_configure(Tex *t) { ST(AirS); bq_lowpass(&s->lpL, 210 + TONE * 620, 0.6f, SR); bq_lowpass(&s->lpR, 216 + TONE * 620, 0.6f, SR); bq_peak(&s->hullL, 88, 2.5f, 6, SR); bq_peak(&s->hullR, 91, 2.5f, 6, SR); bq_highpass(&s->hissL, 2200, 0.7f, SR); bq_highpass(&s->hissR, 2250, 0.7f, SR); s->hissLevel = 0.04f + TONE * 0.20f; s->turbDepth = 0.04f + MOTION * 0.22f; }
static void air_next(Tex *t, float *L, float *R) { ST(AirS); float breathe = 1 + drift(&s->turb) * s->turbDepth, colour = drift(&s->spectral) * 0.2f;
    float bl = brown(&s->brownL, rng_bipolar(&s->rngL)), br = brown(&s->brownR, rng_bipolar(&s->rngR));
    *L = bq(&s->hullL, bq(&s->lpL, bl)) * 2.0f * breathe + bq(&s->hissL, pink(&s->pinkL, rng_bipolar(&s->rngL))) * (s->hissLevel + colour * 0.05f);
    *R = bq(&s->hullR, bq(&s->lpR, br)) * 2.0f * breathe + bq(&s->hissR, pink(&s->pinkR, rng_bipolar(&s->rngR))) * (s->hissLevel + colour * 0.05f); }
static Tex *air_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); AirS *s = calloc(1, sizeof *s); s->rngL = rng_make(0xA1F1); s->rngR = rng_make(0xA1F2); s->turb = drift_make(0xA1F3); s->spectral = drift_make(0xA1F4); bq_init(&s->lpL); bq_init(&s->lpR); bq_init(&s->hullL); bq_init(&s->hullR); bq_init(&s->hissL); bq_init(&s->hissR);
    t->id = "airliner"; t->tone = tone; t->motion = motion; t->build = air_build; t->configure = air_configure; t->next = air_next; t->st = s; return t; }

// --- Train
typedef struct { Rng rngL, rngR, clackRNG; Brown brownL, brownR; Biquad lpL, lpR, hpL, hpR; Bank grains; Drift sway; int intervalSamples, countdown, inPair; float clackLevel; } TrainS;
static void train_build(Tex *t) { ST(TrainS); s->grains = bank_make(16, SR, 0x7A15); drift_prepare(&s->sway, 0.08f, SR); s->countdown = 1000; }
static void train_configure(Tex *t) { ST(TrainS); bq_lowpass(&s->lpL, 240 + TONE * 900, 0.7f, SR); bq_lowpass(&s->lpR, 248 + TONE * 900, 0.7f, SR); bq_highpass(&s->hpL, 35, 0.7f, SR); bq_highpass(&s->hpR, 36, 0.7f, SR); float perSecond = 0.9f + MOTION * 1.6f; int iv = (int)(SR / perSecond); s->intervalSamples = iv > 2000 ? iv : 2000; s->clackLevel = 0.10f + MOTION * 0.34f; }
static void train_next(Tex *t, float *L, float *R) { ST(TrainS); float swayV = 1 + drift(&s->sway) * 0.16f;
    float bl = brown(&s->brownL, rng_bipolar(&s->rngL)), br = brown(&s->brownR, rng_bipolar(&s->rngR));
    float l = bq(&s->hpL, bq(&s->lpL, bl)) * 1.9f * swayV, r = bq(&s->hpR, bq(&s->lpR, br)) * 1.9f * swayV;
    if (--s->countdown <= 0) { float pan = 0.2f + rng_uniform(&s->clackRNG) * 0.6f; bank_trigger(&s->grains, 150 + rng_uniform(&s->clackRNG) * 420, 0.020f + rng_uniform(&s->clackRNG) * 0.035f, s->clackLevel * (0.6f + rng_uniform(&s->clackRNG) * 0.6f), 0.62f, pan, 4 + rng_uniform(&s->clackRNG) * 6, 0.0035f);
        if (s->inPair) { s->inPair = 0; s->countdown = s->intervalSamples; } else { s->inPair = 1; s->countdown = (int)((float)s->intervalSamples * (0.13f + rng_uniform(&s->clackRNG) * 0.06f)); } }
    float gl, gr; bank_next(&s->grains, &gl, &gr); *L = l + gl; *R = r + gr; }
static Tex *train_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); TrainS *s = calloc(1, sizeof *s); s->rngL = rng_make(0x7A11); s->rngR = rng_make(0x7A12); s->clackRNG = rng_make(0x7A13); s->sway = drift_make(0x7A14); s->intervalSamples = 24000; bq_init(&s->lpL); bq_init(&s->lpR); bq_init(&s->hpL); bq_init(&s->hpR);
    t->id = "train"; t->tone = tone; t->motion = motion; t->build = train_build; t->configure = train_configure; t->next = train_next; t->st = s; return t; }

// --- Plain noise
typedef struct { int colour; Rng common, indepL, indepR; Pink pinkC, pinkL, pinkR; Brown brownC, brownL, brownR; Biquad tiltL, tiltR, tilt2L, tilt2R; float width; } NoiseS;
static void noise_build(Tex *t) { (void)t; }
static void noise_configure(Tex *t) { ST(NoiseS); float db = (TONE - 0.5f) * 16; bq_highshelf(&s->tiltL, 1800, db, SR); bq_highshelf(&s->tiltR, 1830, db, SR); bq_lowshelf(&s->tilt2L, 320, -db * 0.7f, SR); bq_lowshelf(&s->tilt2R, 325, -db * 0.7f, SR); s->width = MOTION; }
static void noise_next(Tex *t, float *L, float *R) { ST(NoiseS); float wc = rng_bipolar(&s->common), wl = rng_bipolar(&s->indepL), wr = rng_bipolar(&s->indepR), c, il, ir;
    if (s->colour == 0) { c = wc * 0.4f; il = wl * 0.4f; ir = wr * 0.4f; } else if (s->colour == 1) { c = pink(&s->pinkC, wc) * 1.5f; il = pink(&s->pinkL, wl) * 1.5f; ir = pink(&s->pinkR, wr) * 1.5f; } else { c = brown(&s->brownC, wc) * 0.9f; il = brown(&s->brownL, wl) * 0.9f; ir = brown(&s->brownR, wr) * 0.9f; }
    float l = lerpf_(c, il, s->width), r = lerpf_(c, ir, s->width); *L = bq(&s->tilt2L, bq(&s->tiltL, l)); *R = bq(&s->tilt2R, bq(&s->tiltR, r)); }
static Tex *noise_make(const char *id, int colour, float tone, float motion) { Tex *t = calloc(1, sizeof *t); NoiseS *s = calloc(1, sizeof *s); s->colour = colour; s->common = rng_make(0x0C0F0001); s->indepL = rng_make(0x0A11); s->indepR = rng_make(0x0A22); bq_init(&s->tiltL); bq_init(&s->tiltR); bq_init(&s->tilt2L); bq_init(&s->tilt2R);
    t->id = id; t->tone = tone; t->motion = motion; t->build = noise_build; t->configure = noise_configure; t->next = noise_next; t->st = s; return t; }

// --- Waterfall
typedef struct { Rng rngL, rngR; Pink pinkL, pinkR; Brown brownL, brownR; Biquad bodyL, bodyR, sprayL, sprayR; Drift surge; float sprayLevel, surgeDepth; } FallS;
static void fall_build(Tex *t) { ST(FallS); drift_prepare(&s->surge, 0.07f, SR); }
static void fall_configure(Tex *t) { ST(FallS); bq_lowpass(&s->bodyL, 900 + TONE * 2600, 0.6f, SR); bq_lowpass(&s->bodyR, 920 + TONE * 2600, 0.6f, SR); bq_highpass(&s->sprayL, 2600 + TONE * 3200, 0.7f, SR); bq_highpass(&s->sprayR, 2650 + TONE * 3200, 0.7f, SR); s->sprayLevel = 0.12f + TONE * 0.42f; s->surgeDepth = 0.04f + MOTION * 0.16f; }
static void fall_next(Tex *t, float *L, float *R) { ST(FallS); float swell = 1 + drift(&s->surge) * s->surgeDepth, nl = rng_bipolar(&s->rngL), nr = rng_bipolar(&s->rngR);
    float coreL = brown(&s->brownL, nl) * 0.85f + pink(&s->pinkL, nl) * 0.9f, coreR = brown(&s->brownR, nr) * 0.85f + pink(&s->pinkR, nr) * 0.9f;
    *L = bq(&s->bodyL, coreL) * 1.5f * swell + bq(&s->sprayL, pink(&s->pinkL, nl)) * s->sprayLevel; *R = bq(&s->bodyR, coreR) * 1.5f * swell + bq(&s->sprayR, pink(&s->pinkR, nr)) * s->sprayLevel; }
static Tex *fall_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); FallS *s = calloc(1, sizeof *s); s->rngL = rng_make(0xA401); s->rngR = rng_make(0xA402); s->surge = drift_make(0xA403); bq_init(&s->bodyL); bq_init(&s->bodyR); bq_init(&s->sprayL); bq_init(&s->sprayR);
    t->id = "waterfall"; t->tone = tone; t->motion = motion; t->build = fall_build; t->configure = fall_configure; t->next = fall_next; t->st = s; return t; }

// --- Blizzard
typedef struct { Rng rngL, rngR; Pink pinkL, pinkR; Biquad bandL, bandR, hissL, hissR; Drift centerDrift, gustDrift; int coefCounter; float centerBase, centerRange, hissLevel, gustDepth; } BlizS;
static void bliz_build(Tex *t) { ST(BlizS); drift_prepare(&s->centerDrift, 0.12f, SR); drift_prepare(&s->gustDrift, 0.06f, SR); }
static void bliz_configure(Tex *t) { ST(BlizS); s->centerBase = 220 + TONE * 520; s->centerRange = 120 + TONE * 300; s->hissLevel = 0.26f + TONE * 0.34f; s->gustDepth = 0.22f + MOTION * 0.62f; bq_bandpass(&s->hissL, 1600, 0.5f, SR); bq_bandpass(&s->hissR, 1660, 0.5f, SR); }
static void bliz_next(Tex *t, float *L, float *R) { ST(BlizS); float wander = drift(&s->centerDrift);
    if (--s->coefCounter <= 0) { s->coefCounter = 32; float center = clampf_(s->centerBase + wander * s->centerRange, 60, SR * 0.4f); bq_bandpass(&s->bandL, center, 0.9f, SR); bq_bandpass(&s->bandR, center * 1.05f, 0.9f, SR); }
    float nl = pink(&s->pinkL, rng_bipolar(&s->rngL)), nr = pink(&s->pinkR, rng_bipolar(&s->rngR));
    float l = bq(&s->bandL, nl) * 2.0f + bq(&s->hissL, nl) * s->hissLevel * 1.8f, r = bq(&s->bandR, nr) * 2.0f + bq(&s->hissR, nr) * s->hissLevel * 1.8f;
    float gust = clampf_(1 + drift(&s->gustDrift) * s->gustDepth, 0.2f, 2.0f) * 0.6f; *L = l * gust; *R = r * gust; }
static Tex *bliz_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); BlizS *s = calloc(1, sizeof *s); s->rngL = rng_make(0xB201); s->rngR = rng_make(0xB202); s->centerDrift = drift_make(0xB203); s->gustDrift = drift_make(0xB204); bq_init(&s->bandL); bq_init(&s->bandR); bq_init(&s->hissL); bq_init(&s->hissR);
    t->id = "blizzard"; t->tone = tone; t->motion = motion; t->build = bliz_build; t->configure = bliz_configure; t->next = bliz_next; t->st = s; return t; }

// --- Distant thunder
typedef struct { Rng rng, noiseL, noiseR, airL, airR; Brown brownL, brownR; Pink pinkL, pinkR; Biquad airLPL, airLPR, rumL, rumR; OnePole attack, body; Drift roll; int gateSamples, countdown; float strikeLevel, strikePan; } ThunderS;
static void thunder_build(Tex *t) { ST(ThunderS); op_tc(&s->attack, 0.55f, SR); op_tc(&s->body, 1.1f, SR); drift_prepare(&s->roll, 1.1f, SR); bq_lowpass(&s->airLPL, 600, 0.6f, SR); bq_lowpass(&s->airLPR, 620, 0.6f, SR); s->countdown = (int)(SR * 5); }
static void thunder_configure(Tex *t) { ST(ThunderS); float cutoff = 55 + (1 - TONE) * 340; bq_lowpass(&s->rumL, cutoff, 0.7f, SR); bq_lowpass(&s->rumR, cutoff * 1.06f, 0.7f, SR); }
static void thunder_next(Tex *t, float *L, float *R) { ST(ThunderS);
    if (--s->countdown <= 0) { float mean = 75 - MOTION * 60, jitter = 0.4f + rng_uniform(&s->rng) * 1.5f; s->countdown = (int)fmaxf(SR * mean * jitter, SR * 6); s->gateSamples = (int)(SR * (0.6f + rng_uniform(&s->rng) * 2.2f)); s->strikeLevel = 0.28f + rng_uniform(&s->rng) * 0.30f; s->strikePan = 0.3f + rng_uniform(&s->rng) * 0.4f; }
    float gate = 0; if (s->gateSamples > 0) { s->gateSamples--; gate = s->strikeLevel; }
    float env = op(&s->body, op(&s->attack, gate)), rolling = env * (1 + drift(&s->roll) * 0.5f), l = 0, r = 0;
    if (rolling > 0.0008f) { l = bq(&s->rumL, brown(&s->brownL, rng_bipolar(&s->noiseL))) * rolling * (1 - s->strikePan) * 2.6f; r = bq(&s->rumR, brown(&s->brownR, rng_bipolar(&s->noiseR))) * rolling * s->strikePan * 2.6f; }
    l += bq(&s->airLPL, pink(&s->pinkL, rng_bipolar(&s->airL))) * 0.09f; r += bq(&s->airLPR, pink(&s->pinkR, rng_bipolar(&s->airR))) * 0.09f; *L = l; *R = r; }
static Tex *thunder_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); ThunderS *s = calloc(1, sizeof *s); s->rng = rng_make(0xD701); s->noiseL = rng_make(0xD702); s->noiseR = rng_make(0xD703); s->airL = rng_make(0xD704); s->airR = rng_make(0xD705); s->roll = drift_make(0xD706); bq_init(&s->airLPL); bq_init(&s->airLPR); bq_init(&s->rumL); bq_init(&s->rumR);
    t->id = "thunder.distant"; t->tone = tone; t->motion = motion; t->build = thunder_build; t->configure = thunder_configure; t->next = thunder_next; t->st = s; return t; }

// --- Heartbeat
typedef struct { Rng rng, noiseL, noiseR; Brown brownL, brownR; Biquad flowL, flowR; Drift flowDrift; Bank grains; int periodSamples, counter, didSecond, secondBeatAt; float thumpFrequency; } HeartS;
static void heart_build(Tex *t) { ST(HeartS); s->grains = bank_make(8, SR, 0x4B04); drift_prepare(&s->flowDrift, 0.13f, SR); s->counter = 0; }
static void heart_configure(Tex *t) { ST(HeartS); float bpm = 48 + MOTION * 30; int p = (int)(SR * 60 / bpm); s->periodSamples = p > 1000 ? p : 1000; s->secondBeatAt = (int)((float)s->periodSamples * 0.30f); float cutoff = 130 + TONE * 320; bq_lowpass(&s->flowL, cutoff, 0.7f, SR); bq_lowpass(&s->flowR, cutoff * 1.05f, 0.7f, SR); s->thumpFrequency = 44 + TONE * 26; }
static void heart_thump(HeartS *s, int strong) { bank_trigger(&s->grains, s->thumpFrequency * (strong ? 1 : 1.18f), strong ? 0.075f : 0.055f, (strong ? 0.62f : 0.34f) * (0.9f + rng_uniform(&s->rng) * 0.2f), 0.42f, 0.5f, 1.6f, strong ? 0.014f : 0.011f); }
static void heart_next(Tex *t, float *L, float *R) { ST(HeartS); s->counter++; if (s->counter >= s->periodSamples) { s->counter = 0; s->didSecond = 0; heart_thump(s, 1); } else if (!s->didSecond && s->counter >= s->secondBeatAt) { s->didSecond = 1; heart_thump(s, 0); }
    float surge = 1 + drift(&s->flowDrift) * 0.22f; float l = bq(&s->flowL, brown(&s->brownL, rng_bipolar(&s->noiseL))) * 1.5f * surge, r = bq(&s->flowR, brown(&s->brownR, rng_bipolar(&s->noiseR))) * 1.5f * surge;
    float gl, gr; bank_next(&s->grains, &gl, &gr); *L = l + gl; *R = r + gr; }
static Tex *heart_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); HeartS *s = calloc(1, sizeof *s); s->rng = rng_make(0x4BEA70); s->noiseL = rng_make(0x4B01); s->noiseR = rng_make(0x4B02); s->flowDrift = drift_make(0x4B03); s->periodSamples = 48000; s->thumpFrequency = 54; bq_init(&s->flowL); bq_init(&s->flowR);
    t->id = "heartbeat"; t->tone = tone; t->motion = motion; t->build = heart_build; t->configure = heart_configure; t->next = heart_next; t->st = s; return t; }

// --- Purr
typedef struct { Rng rngL, rngR; Brown brownL, brownR; Biquad bandL, bandR; Drift breath; float phase, rate, depth; } PurrS;
static void purr_build(Tex *t) { ST(PurrS); drift_prepare(&s->breath, 0.22f, SR); }
static void purr_configure(Tex *t) { ST(PurrS); float center = 70 + TONE * 190; bq_bandpass(&s->bandL, center, 0.9f, SR); bq_bandpass(&s->bandR, center * 1.06f, 0.9f, SR); s->rate = 21 + TONE * 9; s->depth = 0.35f + MOTION * 0.55f; }
static void purr_next(Tex *t, float *L, float *R) { ST(PurrS); s->phase += s->rate / SR; if (s->phase >= 1) s->phase -= 1;
    float raw = 0.5f - 0.5f * cosf(2 * PI * s->phase), shaped = raw * raw * (3 - 2 * raw), mod = 1 - s->depth + s->depth * shaped, breathing = 0.72f + 0.38f * (0.5f + 0.5f * drift(&s->breath));
    float l = bq(&s->bandL, brown(&s->brownL, rng_bipolar(&s->rngL))) * 2.4f, r = bq(&s->bandR, brown(&s->brownR, rng_bipolar(&s->rngR))) * 2.4f, gain = mod * breathing; *L = l * gain; *R = r * gain; }
static Tex *purr_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); PurrS *s = calloc(1, sizeof *s); s->rngL = rng_make(0x9011); s->rngR = rng_make(0x9012); s->breath = drift_make(0x9013); s->rate = 25; s->depth = 0.7f; bq_init(&s->bandL); bq_init(&s->bandR);
    t->id = "purr"; t->tone = tone; t->motion = motion; t->build = purr_build; t->configure = purr_configure; t->next = purr_next; t->st = s; return t; }

// --- Frogs
typedef struct { int countdown, pulsesLeft, pulseSamples, gapSamples, inPulse; float phase, frequency, pan, amp; } Frog;
typedef struct { Frog f[6]; OnePole env[6]; Rng rng, bedL, bedR; Pink pinkL, pinkR; Biquad bedLPL, bedLPR, formantL, formantR; int activeCount; float baseFrequency; } FrogS;
static void frog_build(Tex *t) { ST(FrogS); for (int i = 0; i < 6; i++) { s->f[i].countdown = (int)(rng_uniform(&s->rng) * SR * 4); op_tc(&s->env[i], 0.008f, SR); } bq_lowpass(&s->bedLPL, 700, 0.6f, SR); bq_lowpass(&s->bedLPR, 720, 0.6f, SR); }
static void frog_configure(Tex *t) { ST(FrogS); s->baseFrequency = 190 + TONE * 420; s->activeCount = 2 + (int)(MOTION * 4); bq_bandpass(&s->formantL, s->baseFrequency * 2.6f, 2.2f, SR); bq_bandpass(&s->formantR, s->baseFrequency * 2.66f, 2.2f, SR); }
static void frog_next(Tex *t, float *L, float *R) { ST(FrogS); float left = 0, right = 0; int n = s->activeCount < 6 ? s->activeCount : 6;
    for (int i = 0; i < n; i++) { Frog *c = &s->f[i];
        if (c->pulsesLeft <= 0) { if (--c->countdown <= 0) { c->pulsesLeft = 1 + (int)(rng_uniform(&s->rng) * 5); c->pulseSamples = (int)(SR * (0.045f + rng_uniform(&s->rng) * 0.075f)); c->gapSamples = (int)(SR * (0.050f + rng_uniform(&s->rng) * 0.090f)); c->frequency = s->baseFrequency * (0.78f + rng_uniform(&s->rng) * 0.5f); c->pan = rng_uniform(&s->rng); c->amp = 0.10f + rng_uniform(&s->rng) * 0.20f; c->inPulse = 1; c->countdown = c->pulseSamples; } }
        float target = 0;
        if (c->pulsesLeft > 0) { c->countdown--; if (c->inPulse) { target = 1; if (c->countdown <= 0) { c->inPulse = 0; c->countdown = c->gapSamples; c->pulsesLeft--; if (c->pulsesLeft <= 0) c->countdown = (int)(SR * (1.2f + rng_uniform(&s->rng) * 5.5f)); } } else if (c->countdown <= 0) { c->inPulse = 1; c->countdown = c->pulseSamples; } }
        float env = op(&s->env[i], target);
        if (env > 0.001f) { c->phase += c->frequency / SR; if (c->phase >= 1) c->phase -= 1; float p = c->phase; float v = (sinf(2 * PI * p) + 0.5f * sinf(4 * PI * p) + 0.22f * sinf(6 * PI * p)) * env * c->amp; left += v * (1 - c->pan); right += v * c->pan; } }
    left = left * 0.6f + bq(&s->formantL, left) * 0.7f; right = right * 0.6f + bq(&s->formantR, right) * 0.7f;
    *L = left + bq(&s->bedLPL, pink(&s->pinkL, rng_bipolar(&s->bedL))) * 0.13f; *R = right + bq(&s->bedLPR, pink(&s->pinkR, rng_bipolar(&s->bedR))) * 0.13f; }
static Tex *frog_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); FrogS *s = calloc(1, sizeof *s); s->rng = rng_make(0xF206); s->bedL = rng_make(0xF207); s->bedR = rng_make(0xF208); s->activeCount = 4; s->baseFrequency = 320; bq_init(&s->bedLPL); bq_init(&s->bedLPR); bq_init(&s->formantL); bq_init(&s->formantR); for (int i = 0; i < 6; i++) { s->f[i].frequency = 320; s->f[i].pan = 0.5f; s->f[i].amp = 0.3f; s->env[i].a = 0.01f; }
    t->id = "frogs"; t->tone = tone; t->motion = motion; t->build = frog_build; t->configure = frog_configure; t->next = frog_next; t->st = s; return t; }

// --- Birds
typedef struct { int countdown, notesLeft, noteSamples, elapsed, singing; float startF, endF, phase, pan, amp; } Bird;
typedef struct { Bird b[6]; Rng rng, airL, airR; Pink pinkL, pinkR; Biquad airLPL, airLPR; int activeCount; float baseFrequency; } BirdS;
static void bird_start(BirdS *s, Bird *b) { b->elapsed = 0; b->noteSamples = (int)(SR * (0.045f + rng_uniform(&s->rng) * 0.11f)); float start = s->baseFrequency * (0.8f + rng_uniform(&s->rng) * 0.55f); int rising = rng_uniform(&s->rng) < 0.68f; float span = 1 + rng_uniform(&s->rng) * 0.55f; b->startF = start; b->endF = rising ? start * span : start / span; }
static void bird_build(Tex *t) { ST(BirdS); for (int i = 0; i < 6; i++) s->b[i].countdown = (int)(rng_uniform(&s->rng) * SR * 5); bq_lowpass(&s->airLPL, 1400, 0.6f, SR); bq_lowpass(&s->airLPR, 1430, 0.6f, SR); }
static void bird_configure(Tex *t) { ST(BirdS); s->baseFrequency = 2200 + TONE * 2600; s->activeCount = 2 + (int)(MOTION * 4); }
static void bird_next(Tex *t, float *L, float *R) { ST(BirdS); float left = 0, right = 0; int n = s->activeCount < 6 ? s->activeCount : 6;
    for (int i = 0; i < n; i++) { Bird *b = &s->b[i];
        if (!b->singing) { if (--b->countdown <= 0) { b->singing = 1; b->notesLeft = 1 + (int)(rng_uniform(&s->rng) * 4); b->pan = rng_uniform(&s->rng); b->amp = 0.06f + rng_uniform(&s->rng) * 0.13f; bird_start(s, b); } continue; }
        float progress = (float)b->elapsed / (float)(b->noteSamples > 1 ? b->noteSamples : 1); b->elapsed++;
        if (progress >= 1) { b->notesLeft--; if (b->notesLeft > 0) bird_start(s, b); else { b->singing = 0; b->countdown = (int)(SR * (0.9f + rng_uniform(&s->rng) * 5.0f)); } continue; }
        float env = 0.5f - 0.5f * cosf(2 * PI * progress), freq = lerpf_(b->startF, b->endF, progress); b->phase += freq / SR; if (b->phase >= 1) b->phase -= 1;
        float p = b->phase, v = (sinf(2 * PI * p) + 0.28f * sinf(4 * PI * p)) * env * b->amp; left += v * (1 - b->pan); right += v * b->pan; }
    *L = left + bq(&s->airLPL, pink(&s->pinkL, rng_bipolar(&s->airL))) * 0.10f; *R = right + bq(&s->airLPR, pink(&s->pinkR, rng_bipolar(&s->airR))) * 0.10f; }
static Tex *bird_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); BirdS *s = calloc(1, sizeof *s); s->rng = rng_make(0xB1D5); s->airL = rng_make(0xB1D6); s->airR = rng_make(0xB1D7); s->activeCount = 4; s->baseFrequency = 3200; bq_init(&s->airLPL); bq_init(&s->airLPR);
    t->id = "birds"; t->tone = tone; t->motion = motion; t->build = bird_build; t->configure = bird_configure; t->next = bird_next; t->st = s; return t; }

// --- Air conditioner
typedef struct { Rng rngL, rngR; Pink pinkL, pinkR; Brown brownL, brownR; Biquad airLPL, airLPR, humL, humR, harmL, harmR; Drift cycle; float humLevel, cycleDepth; } ACS;
static void ac_build(Tex *t) { ST(ACS); drift_prepare(&s->cycle, 0.035f, SR); }
static void ac_configure(Tex *t) { ST(ACS); bq_lowpass(&s->airLPL, 1600 + TONE * 4200, 0.6f, SR); bq_lowpass(&s->airLPR, 1640 + TONE * 4200, 0.6f, SR); bq_peak(&s->humL, 118, 6, 5 + MOTION * 9, SR); bq_peak(&s->humR, 120, 6, 5 + MOTION * 9, SR); bq_peak(&s->harmL, 236, 7, 3 + MOTION * 5, SR); bq_peak(&s->harmR, 240, 7, 3 + MOTION * 5, SR); s->humLevel = 0.3f + MOTION * 0.5f; s->cycleDepth = 0.03f + MOTION * 0.09f; }
static void ac_next(Tex *t, float *L, float *R) { ST(ACS); float breathing = 1 + drift(&s->cycle) * s->cycleDepth, nl = rng_bipolar(&s->rngL), nr = rng_bipolar(&s->rngR);
    float airL = bq(&s->airLPL, pink(&s->pinkL, nl)) * 1.3f, airR = bq(&s->airLPR, pink(&s->pinkR, nr)) * 1.3f, bodyL = bq(&s->harmL, bq(&s->humL, brown(&s->brownL, nl))) * s->humLevel * 1.6f, bodyR = bq(&s->harmR, bq(&s->humR, brown(&s->brownR, nr))) * s->humLevel * 1.6f;
    *L = (airL + bodyL) * breathing; *R = (airR + bodyR) * breathing; }
static Tex *ac_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); ACS *s = calloc(1, sizeof *s); s->rngL = rng_make(0xAC01); s->rngR = rng_make(0xAC02); s->cycle = drift_make(0xAC03); bq_init(&s->airLPL); bq_init(&s->airLPR); bq_init(&s->humL); bq_init(&s->humR); bq_init(&s->harmL); bq_init(&s->harmR);
    t->id = "ac"; t->tone = tone; t->motion = motion; t->build = ac_build; t->configure = ac_configure; t->next = ac_next; t->st = s; return t; }

// --- Washer
typedef struct { Rng rngL, rngR; Brown brownL, brownR; Pink pinkL, pinkR; Biquad rumL, rumR, sloshL, sloshR, motorL, motorR; Phasor drum; float motorLevel, sloshDepth; } WashS;
static void wash_build(Tex *t) { ST(WashS); ph_freq(&s->drum, 0.55f, SR); }
static void wash_configure(Tex *t) { ST(WashS); bq_lowpass(&s->rumL, 320 + TONE * 700, 0.7f, SR); bq_lowpass(&s->rumR, 330 + TONE * 700, 0.7f, SR); bq_bandpass(&s->sloshL, 900, 0.8f, SR); bq_bandpass(&s->sloshR, 940, 0.8f, SR); bq_peak(&s->motorL, 96, 5, 4 + TONE * 8, SR); bq_peak(&s->motorR, 98, 5, 4 + TONE * 8, SR); s->motorLevel = 0.3f + TONE * 0.5f; s->sloshDepth = 0.2f + MOTION * 0.6f; ph_freq(&s->drum, 0.38f + MOTION * 0.55f, SR); }
static void wash_next(Tex *t, float *L, float *R) { ST(WashS); float raw = 0.5f - 0.5f * cosf(2 * PI * ph_phase(&s->drum)), sloshEnv = raw * raw, nl = rng_bipolar(&s->rngL), nr = rng_bipolar(&s->rngR);
    float bodyL = bq(&s->motorL, bq(&s->rumL, brown(&s->brownL, nl))) * 1.7f * s->motorLevel, bodyR = bq(&s->motorR, bq(&s->rumR, brown(&s->brownR, nr))) * 1.7f * s->motorLevel;
    float waterL = bq(&s->sloshL, pink(&s->pinkL, nl)) * sloshEnv * s->sloshDepth * 1.4f, waterR = bq(&s->sloshR, pink(&s->pinkR, nr)) * sloshEnv * s->sloshDepth * 1.4f, swell = 0.82f + sloshEnv * 0.3f;
    *L = bodyL * swell + waterL; *R = bodyR * swell + waterR; }
static Tex *wash_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); WashS *s = calloc(1, sizeof *s); s->rngL = rng_make(0x5701); s->rngR = rng_make(0x5702); bq_init(&s->rumL); bq_init(&s->rumR); bq_init(&s->sloshL); bq_init(&s->sloshR); bq_init(&s->motorL); bq_init(&s->motorR);
    t->id = "washer"; t->tone = tone; t->motion = motion; t->build = wash_build; t->configure = wash_configure; t->next = wash_next; t->st = s; return t; }

// --- Dryer
typedef struct { Rng rngL, rngR, thumpRNG; Brown brownL, brownR; Pink pinkL, pinkR; Biquad rumL, rumR, heatL, heatR; Bank grains; int rotationSamples, counter; float heatLevel, thumpLevel; } DryS;
static void dry_build(Tex *t) { ST(DryS); s->grains = bank_make(6, SR, 0x6D04); }
static void dry_configure(Tex *t) { ST(DryS); bq_lowpass(&s->rumL, 280 + TONE * 620, 0.7f, SR); bq_lowpass(&s->rumR, 288 + TONE * 620, 0.7f, SR); bq_bandpass(&s->heatL, 2400, 0.5f, SR); bq_bandpass(&s->heatR, 2460, 0.5f, SR); s->heatLevel = 0.12f + TONE * 0.34f; float perSecond = 0.6f + MOTION * 0.7f; int r = (int)(SR / perSecond); s->rotationSamples = r > 8000 ? r : 8000; s->thumpLevel = 0.10f + MOTION * 0.30f; }
static void dry_next(Tex *t, float *L, float *R) { ST(DryS); s->counter++; if (s->counter >= s->rotationSamples) { s->counter = 0; bank_trigger(&s->grains, 90 + rng_uniform(&s->thumpRNG) * 160, 0.05f + rng_uniform(&s->thumpRNG) * 0.07f, s->thumpLevel * (0.6f + rng_uniform(&s->thumpRNG) * 0.7f), 0.72f, 0.3f + rng_uniform(&s->thumpRNG) * 0.4f, 2.2f, 0.010f); }
    float nl = rng_bipolar(&s->rngL), nr = rng_bipolar(&s->rngR); float l = bq(&s->rumL, brown(&s->brownL, nl)) * 1.9f + bq(&s->heatL, pink(&s->pinkL, nl)) * s->heatLevel, r = bq(&s->rumR, brown(&s->brownR, nr)) * 1.9f + bq(&s->heatR, pink(&s->pinkR, nr)) * s->heatLevel;
    float gl, gr; bank_next(&s->grains, &gl, &gr); *L = l + gl; *R = r + gr; }
static Tex *dry_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); DryS *s = calloc(1, sizeof *s); s->rngL = rng_make(0x6D01); s->rngR = rng_make(0x6D02); s->thumpRNG = rng_make(0x6D03); s->rotationSamples = 48000; bq_init(&s->rumL); bq_init(&s->rumR); bq_init(&s->heatL); bq_init(&s->heatR);
    t->id = "dryer"; t->tone = tone; t->motion = motion; t->build = dry_build; t->configure = dry_configure; t->next = dry_next; t->st = s; return t; }

// --- Highway
typedef struct { Rng rngL, rngR, passRNG; Brown brownL, brownR; Pink pinkL, pinkR; Biquad roadL, roadR, passL, passR; OnePole passEnv; int passSamples, passElapsed, countdown, passCoefCounter; float passPan, passLevel, passProgress; } HwyS;
static void hwy_build(Tex *t) { ST(HwyS); op_tc(&s->passEnv, 0.25f, SR); s->countdown = (int)(SR * 3); }
static void hwy_configure(Tex *t) { ST(HwyS); bq_lowpass(&s->roadL, 380 + TONE * 1400, 0.6f, SR); bq_lowpass(&s->roadR, 390 + TONE * 1400, 0.6f, SR); }
static void hwy_next(Tex *t, float *L, float *R) { ST(HwyS); s->countdown--;
    if (s->countdown <= 0 && s->passSamples == 0) { float mean = 20 - MOTION * 17; int cd = (int)(SR * mean * (0.4f + rng_uniform(&s->passRNG) * 1.4f)); int half = (int)SR / 2; s->countdown = cd > half ? cd : half; s->passSamples = (int)(SR * (1.6f + rng_uniform(&s->passRNG) * 2.6f)); s->passElapsed = 0; s->passPan = rng_uniform(&s->passRNG) < 0.5f ? 0.15f : 0.85f; s->passLevel = 0.12f + rng_uniform(&s->passRNG) * 0.26f; }
    float pl = 0, pr = 0;
    if (s->passSamples > 0) { s->passProgress = (float)s->passElapsed / (float)s->passSamples; s->passElapsed++; if (s->passElapsed >= s->passSamples) { s->passSamples = 0; s->passElapsed = 0; }
        if (--s->passCoefCounter <= 0) { s->passCoefCounter = 64; float center = lerpf_(900, 380, s->passProgress); bq_bandpass(&s->passL, center, 1.1f, SR); bq_bandpass(&s->passR, center * 1.05f, 1.1f, SR); }
        float shape = sinf(PI * clampf_(s->passProgress, 0, 1)), env = op(&s->passEnv, shape * s->passLevel), pan = lerpf_(s->passPan, 1 - s->passPan, s->passProgress), nl = pink(&s->pinkL, rng_bipolar(&s->rngL));
        float v = bq(&s->passL, nl) * env * 2.2f; pl = v * (1 - pan); pr = bq(&s->passR, nl) * env * 2.2f * pan; }
    else op(&s->passEnv, 0);
    *L = bq(&s->roadL, brown(&s->brownL, rng_bipolar(&s->rngL))) * 1.8f + pl; *R = bq(&s->roadR, brown(&s->brownR, rng_bipolar(&s->rngR))) * 1.8f + pr; }
static Tex *hwy_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); HwyS *s = calloc(1, sizeof *s); s->rngL = rng_make(0x4701); s->rngR = rng_make(0x4702); s->passRNG = rng_make(0x4703); s->passPan = 0.5f; bq_init(&s->roadL); bq_init(&s->roadR); bq_init(&s->passL); bq_init(&s->passR);
    t->id = "highway"; t->tone = tone; t->motion = motion; t->build = hwy_build; t->configure = hwy_configure; t->next = hwy_next; t->st = s; return t; }

// --- Cafe
typedef struct { float phase, rate, pan, level, target; int countdown; Biquad band; float center; } Speaker;
typedef struct { Speaker sp[4]; Rng rng, noiseL, noiseR; Pink pinkL, pinkR; Biquad roomL, roomR; Rng clinkRNG; Bank grains; OnePole levelSmooth[4]; float clinkProbability; int coefCounter; } CafeS;
static void cafe_build(Tex *t) { ST(CafeS); s->grains = bank_make(8, SR, 0xCA05); for (int i = 0; i < 4; i++) { s->sp[i].rate = 3.0f + rng_uniform(&s->rng) * 2.6f; s->sp[i].pan = rng_uniform(&s->rng); s->sp[i].center = 500 + rng_uniform(&s->rng) * 1600; s->sp[i].countdown = (int)(rng_uniform(&s->rng) * SR * 3); op_tc(&s->levelSmooth[i], 0.25f, SR); } bq_lowpass(&s->roomL, 3200, 0.6f, SR); bq_lowpass(&s->roomR, 3260, 0.6f, SR); }
static void cafe_configure(Tex *t) { ST(CafeS); s->clinkProbability = (0.05f + MOTION * 0.5f) / SR; s->coefCounter = 0; }
static void cafe_next(Tex *t, float *L, float *R) { ST(CafeS); float left = 0, right = 0; int refresh = s->coefCounter <= 0; if (refresh) s->coefCounter = 64; s->coefCounter--;
    for (int i = 0; i < 4; i++) { Speaker *k = &s->sp[i]; if (--k->countdown <= 0) { int talking = rng_uniform(&s->rng) < (0.4f + MOTION * 0.45f); k->target = talking ? (0.25f + rng_uniform(&s->rng) * 0.6f) : 0; k->countdown = (int)(SR * (0.5f + rng_uniform(&s->rng) * 2.4f)); if (talking) { k->center = 420 + rng_uniform(&s->rng) * (900 + TONE * 1800); k->rate = 3.0f + rng_uniform(&s->rng) * 2.8f; } }
        if (refresh) bq_bandpass(&k->band, k->center, 1.6f, SR);
        k->level = op(&s->levelSmooth[i], k->target); if (k->level <= 0.002f) continue;
        k->phase += k->rate / SR; if (k->phase >= 1) k->phase -= 1; float syllable = 0.35f + 0.65f * (0.5f - 0.5f * cosf(2 * PI * k->phase));
        float source = pink(&s->pinkL, rng_bipolar(&s->noiseL)), v = bq(&k->band, source) * k->level * syllable * 1.5f; left += v * (1 - k->pan); right += v * k->pan; }
    if (rng_uniform(&s->clinkRNG) < s->clinkProbability) bank_trigger(&s->grains, 1800 + rng_uniform(&s->clinkRNG) * 2200, 0.06f + rng_uniform(&s->clinkRNG) * 0.14f, 0.028f + rng_uniform(&s->clinkRNG) * 0.045f, 0.25f, rng_uniform(&s->clinkRNG), 14 + rng_uniform(&s->clinkRNG) * 18, 0.006f);
    float gl, gr; bank_next(&s->grains, &gl, &gr); left = bq(&s->roomL, left) + gl; right = bq(&s->roomR, right) + gr; left += pink(&s->pinkL, rng_bipolar(&s->noiseL)) * 0.05f; right += pink(&s->pinkR, rng_bipolar(&s->noiseR)) * 0.05f; *L = left; *R = right; }
static Tex *cafe_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); CafeS *s = calloc(1, sizeof *s); s->rng = rng_make(0xCA01); s->noiseL = rng_make(0xCA02); s->noiseR = rng_make(0xCA03); s->clinkRNG = rng_make(0xCA04); bq_init(&s->roomL); bq_init(&s->roomR); for (int i = 0; i < 4; i++) { bq_init(&s->sp[i].band); s->sp[i].rate = 4; s->sp[i].pan = 0.5f; s->sp[i].center = 900; s->levelSmooth[i].a = 0.01f; }
    t->id = "cafe"; t->tone = tone; t->motion = motion; t->build = cafe_build; t->configure = cafe_configure; t->next = cafe_next; t->st = s; return t; }

// --- Clock
typedef struct { Bank grains; Rng rng, roomL, roomR; Brown brownL, brownR; Biquad roomLPL, roomLPR; int periodSamples, counter, isTick; float woodFrequency; } ClockS;
static void clock_build(Tex *t) { ST(ClockS); s->grains = bank_make(6, SR, 0xC104); bq_lowpass(&s->roomLPL, 320, 0.6f, SR); bq_lowpass(&s->roomLPR, 330, 0.6f, SR); }
static void clock_configure(Tex *t) { ST(ClockS); float perSecond = 0.7f + MOTION * 0.7f; int p = (int)(SR / perSecond); s->periodSamples = p > 6000 ? p : 6000; s->woodFrequency = 1100 + TONE * 2400; }
static void clock_next(Tex *t, float *L, float *R) { ST(ClockS); s->counter++; if (s->counter >= s->periodSamples) { s->counter = 0; float f = s->isTick ? s->woodFrequency : s->woodFrequency * 0.76f;
        bank_trigger(&s->grains, f, 0.010f + rng_uniform(&s->rng) * 0.010f, (s->isTick ? 0.19f : 0.16f) * (0.9f + rng_uniform(&s->rng) * 0.2f), 0.55f, 0.5f, 9, 0.0016f); bank_trigger(&s->grains, f * 0.31f, 0.030f, s->isTick ? 0.075f : 0.062f, 0.3f, 0.5f, 4, 0.003f); s->isTick = !s->isTick; }
    float gl, gr; bank_next(&s->grains, &gl, &gr); *L = bq(&s->roomLPL, brown(&s->brownL, rng_bipolar(&s->roomL))) * 0.5f + gl; *R = bq(&s->roomLPR, brown(&s->brownR, rng_bipolar(&s->roomR))) * 0.5f + gr; }
static Tex *clock_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); ClockS *s = calloc(1, sizeof *s); s->rng = rng_make(0xC101); s->roomL = rng_make(0xC102); s->roomR = rng_make(0xC103); s->periodSamples = 48000; s->isTick = 1; s->woodFrequency = 1800; bq_init(&s->roomLPL); bq_init(&s->roomLPR);
    t->id = "clock"; t->tone = tone; t->motion = motion; t->build = clock_build; t->configure = clock_configure; t->next = clock_next; t->st = s; return t; }

// --- Chimes
static const float CHIME_RATIOS[6] = {1.0f, 9.0f / 8.0f, 5.0f / 4.0f, 3.0f / 2.0f, 5.0f / 3.0f, 2.0f};
typedef struct { Bank grains; Rng rng, windL, windR; Pink pinkL, pinkR; Biquad windLPL, windLPR; Drift gust; float baseFrequency, strikeProbability; int cooldown; } ChimeS;
static void chime_build(Tex *t) { ST(ChimeS); s->grains = bank_make(14, SR, 0xCE05); drift_prepare(&s->gust, 0.10f, SR); bq_lowpass(&s->windLPL, 1100, 0.6f, SR); bq_lowpass(&s->windLPR, 1130, 0.6f, SR); }
static void chime_configure(Tex *t) { ST(ChimeS); s->baseFrequency = 392 + TONE * 480; s->strikeProbability = (0.25f + MOTION * 2.6f) / SR; }
static void chime_next(Tex *t, float *L, float *R) { ST(ChimeS); float breeze = drift(&s->gust), excitement = clampf_(0.35f + breeze * 0.9f, 0, 1.6f);
    if (s->cooldown > 0) s->cooldown--;
    if (s->cooldown == 0 && rng_uniform(&s->rng) < s->strikeProbability * excitement) { float ratio = CHIME_RATIOS[(int)(rng_uniform(&s->rng) * 6) % 6], f = s->baseFrequency * ratio, amp = 0.06f + rng_uniform(&s->rng) * 0.13f, pan = 0.2f + rng_uniform(&s->rng) * 0.6f, decay = 2.2f + rng_uniform(&s->rng) * 3.4f;
        bank_trigger(&s->grains, f, decay, amp, 0, pan, 6, 0.025f); bank_trigger(&s->grains, f * 2.76f, decay * 0.45f, amp * 0.28f, 0, pan, 6, 0.030f); bank_trigger(&s->grains, f * 1.004f, decay * 0.9f, amp * 0.5f, 0, 1 - pan, 6, 0.028f);
        s->cooldown = (int)(SR * (0.10f + rng_uniform(&s->rng) * 0.35f)); }
    float gl, gr; bank_next(&s->grains, &gl, &gr); float wl = bq(&s->windLPL, pink(&s->pinkL, rng_bipolar(&s->windL))) * 0.22f * (0.6f + excitement * 0.5f), wr = bq(&s->windLPR, pink(&s->pinkR, rng_bipolar(&s->windR))) * 0.22f * (0.6f + excitement * 0.5f); *L = gl * 0.85f + wl; *R = gr * 0.85f + wr; }
static Tex *chime_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); ChimeS *s = calloc(1, sizeof *s); s->rng = rng_make(0xCE01); s->windL = rng_make(0xCE02); s->windR = rng_make(0xCE03); s->gust = drift_make(0xCE04); s->baseFrequency = 523; bq_init(&s->windLPL); bq_init(&s->windLPR);
    t->id = "chimes"; t->tone = tone; t->motion = motion; t->build = chime_build; t->configure = chime_configure; t->next = chime_next; t->st = s; return t; }

// --- Bowl
static const float BOWL_RATIOS[3] = {1.0f, 2.74f, 5.42f}; static const float BOWL_LEVELS[3] = {1.0f, 0.34f, 0.12f};
typedef struct { Phasor a[3], b[3]; float level[3]; Rng rng; float amplitude, peak; int attackRemaining; float attackStep, decayPerSample; int countdown; Rng airL, airR; Pink pinkL, pinkR; Biquad airHPL, airHPR; float baseFrequency, beatSpread; } BowlS;
static void bowl_retune(BowlS *s) { for (int i = 0; i < 3; i++) { float f = s->baseFrequency * BOWL_RATIOS[i]; ph_freq(&s->a[i], f, SR); ph_freq(&s->b[i], f * (1 + s->beatSpread), SR); s->level[i] = BOWL_LEVELS[i]; } }
static void bowl_build(Tex *t) { ST(BowlS); bq_highpass(&s->airHPL, 3000, 0.7f, SR); bq_highpass(&s->airHPR, 3060, 0.7f, SR); s->countdown = 1; }
static void bowl_configure(Tex *t) { ST(BowlS); s->baseFrequency = 150 + TONE * 240; s->beatSpread = 0.0012f + MOTION * 0.010f; bowl_retune(s); }
static void bowl_next(Tex *t, float *L, float *R) { ST(BowlS);
    if (--s->countdown <= 0) { s->countdown = (int)(SR * (20 + rng_uniform(&s->rng) * 30)); s->peak = 0.26f + rng_uniform(&s->rng) * 0.12f; s->attackRemaining = (int)(SR * 0.25f); s->attackStep = s->peak / (float)(s->attackRemaining > 1 ? s->attackRemaining : 1); float decaySec = 14 + rng_uniform(&s->rng) * 10; s->decayPerSample = expf(-1 / (decaySec * SR)); for (int i = 0; i < 3; i++) { s->a[i].phase = rng_uniform(&s->rng); s->b[i].phase = rng_uniform(&s->rng); } }
    if (s->attackRemaining > 0) { s->amplitude += s->attackStep; s->attackRemaining--; } else s->amplitude *= s->decayPerSample;
    float v = 0; for (int i = 0; i < 3; i++) { float pair = ph_sine(&s->a[i]) + ph_sine(&s->b[i]) * 0.85f; v += pair * s->level[i]; } v *= s->amplitude * 0.30f;
    *L = v + bq(&s->airHPL, pink(&s->pinkL, rng_bipolar(&s->airL))) * 0.035f; *R = v * 0.97f + bq(&s->airHPR, pink(&s->pinkR, rng_bipolar(&s->airR))) * 0.035f; }
static Tex *bowl_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); BowlS *s = calloc(1, sizeof *s); s->rng = rng_make(0xB001); s->airL = rng_make(0xB002); s->airR = rng_make(0xB003); s->decayPerSample = 0.99999f; s->baseFrequency = 210; s->beatSpread = 0.004f; bq_init(&s->airHPL); bq_init(&s->airHPR);
    t->id = "bowl"; t->tone = tone; t->motion = motion; t->build = bowl_build; t->configure = bowl_configure; t->next = bowl_next; t->st = s; return t; }

// --- Oscillating fan
typedef struct { Rng rngL, rngR; Brown brownL, brownR; Pink pinkL, pinkR; Biquad toneL, toneR, motorL, motorR; Phasor blade, sweep; int coefCounter; float brightness, motorLevel, bladeDepth; } OscS;
static void osc_build(Tex *t) { ST(OscS); ph_freq(&s->blade, 23, SR); ph_freq(&s->sweep, 0.14f, SR); bq_peak(&s->motorL, 112, 5, 5, SR); bq_peak(&s->motorR, 114, 5, 5, SR); }
static void osc_configure(Tex *t) { ST(OscS); s->brightness = 1500 + TONE * 3600; s->motorLevel = 0.28f + TONE * 0.45f; s->bladeDepth = 0.03f + TONE * 0.10f; ph_freq(&s->sweep, 1 / (5 + (1 - MOTION) * 9), SR); }
static void osc_next(Tex *t, float *L, float *R) { ST(OscS); float facing = sinf(2 * PI * ph_phase(&s->sweep)), towards = 1 - fabsf(facing);
    if (--s->coefCounter <= 0) { s->coefCounter = 64; float cutoff = s->brightness * (0.42f + towards * 0.58f); bq_lowpass(&s->toneL, cutoff, 0.6f, SR); bq_lowpass(&s->toneR, cutoff * 1.04f, 0.6f, SR); }
    float nl = rng_bipolar(&s->rngL), nr = rng_bipolar(&s->rngR), coreL = brown(&s->brownL, nl) * 0.8f + pink(&s->pinkL, nl) * 0.5f, coreR = brown(&s->brownR, nr) * 0.8f + pink(&s->pinkR, nr) * 0.5f;
    float l = bq(&s->motorL, bq(&s->toneL, coreL)) * 1.6f * s->motorLevel, r = bq(&s->motorR, bq(&s->toneR, coreR)) * 1.6f * s->motorLevel, chop = 1 + ph_sine(&s->blade) * s->bladeDepth; l *= chop; r *= chop;
    float swell = 0.72f + towards * 0.34f; *L = l * swell * (1 - facing * 0.28f); *R = r * swell * (1 + facing * 0.28f); }
static Tex *osc_make(float tone, float motion) { Tex *t = calloc(1, sizeof *t); OscS *s = calloc(1, sizeof *s); s->rngL = rng_make(0x0F01); s->rngR = rng_make(0x0F02); s->brightness = 2400; s->motorLevel = 0.4f; s->bladeDepth = 0.07f; bq_init(&s->toneL); bq_init(&s->toneR); bq_init(&s->motorL); bq_init(&s->motorR);
    t->id = "fan.oscillating"; t->tone = tone; t->motion = motion; t->build = osc_build; t->configure = osc_configure; t->next = osc_next; t->st = s; return t; }

// ---------------------------------------------------------------- A-weighting (approximate, two biquads)
// A cheap stand-in for perceived loudness: a 2nd-order highpass near 100 Hz and
// a gentle high shelf, close enough to rank textures against each other.
typedef struct { Biquad hp, sh; } AWeight;
static void aw_init(AWeight *a) { bq_init(&a->hp); bq_init(&a->sh); bq_highpass(&a->hp, 120, 0.6f, SR); bq_highshelf(&a->sh, 2500, 3.0f, SR); }
static inline float aw(AWeight *a, float x) { return bq(&a->sh, bq(&a->hp, x)); }

// ---------------------------------------------------------------- catalog defaults (id, tone, motion, level)
typedef struct { Tex *tex; float level; } Entry;

int main(int argc, char **argv) {
    float seconds = argc > 1 ? (float)atof(argv[1]) : 20.0f;
    Entry list[] = {
        { rain_make("rain.light", 0, 0.45f, 0.5f), 0.7f }, { rain_make("rain.heavy", 1, 0.4f, 0.45f), 0.7f }, { rain_make("rain.roof", 2, 0.55f, 0.55f), 0.7f },
        { storm_make(0.65f, 0.4f), 0.7f }, { ocean_make(0.45f, 0.5f), 0.7f }, { stream_make(0.5f, 0.5f), 0.7f },
        { wind_make("wind.plain", 0, 0.4f, 0.45f), 0.7f }, { wind_make("wind.trees", 1, 0.6f, 0.5f), 0.7f }, { fire_make(0.45f, 0.5f), 0.7f },
        { cricket_make(0.5f, 0.4f), 0.5f }, { room_make(0.4f, 0.35f), 0.7f }, { fan_make(0.5f, 0.4f), 0.7f }, { air_make(0.4f, 0.3f), 0.7f }, { train_make(0.45f, 0.5f), 0.7f },
        { thunder_make(0.35f, 0.4f), 0.6f }, { fall_make(0.42f, 0.45f), 0.72f }, { bliz_make(0.4f, 0.5f), 0.68f }, { frog_make(0.45f, 0.4f), 0.5f }, { bird_make(0.5f, 0.45f), 0.45f },
        { purr_make(0.45f, 0.55f), 0.6f }, { heart_make(0.45f, 0.35f), 0.7f }, { osc_make(0.5f, 0.45f), 0.7f }, { ac_make(0.45f, 0.4f), 0.7f }, { wash_make(0.45f, 0.4f), 0.68f }, { dry_make(0.42f, 0.4f), 0.68f },
        { cafe_make(0.45f, 0.45f), 0.55f }, { hwy_make(0.35f, 0.4f), 0.65f }, { clock_make(0.45f, 0.4f), 0.45f }, { chime_make(0.45f, 0.35f), 0.5f }, { bowl_make(0.4f, 0.4f), 0.55f },
        { noise_make("noise.white", 0, 0.5f, 0.5f), 0.5f }, { noise_make("noise.pink", 1, 0.5f, 0.5f), 0.6f }, { noise_make("noise.brown", 2, 0.5f, 0.5f), 0.75f },
    };
    int n = sizeof list / sizeof list[0];
    long frames = (long)(SR * seconds);
    printf("%-16s %8s %8s %8s %8s %9s\n", "id", "rms_dB", "aw_dB", "peak", "cent_Hz", "at_level");
    for (int i = 0; i < n; i++) {
        Tex *t = list[i].tex; t->build(t); t->configure(t);
        AWeight awL, awR; aw_init(&awL); aw_init(&awR);
        double sum = 0, asum = 0, peak = 0, hf = 0, lf = 0; Biquad split; bq_init(&split); bq_highpass(&split, 1000, 0.7f, SR);
        long skip = (long)(SR * 2); // let filters and drifts settle
        for (long k = 0; k < frames + skip; k++) {
            if ((k & 63) == 0) t->configure(t);
            float l, r; t->next(t, &l, &r);
            if (k < skip) continue;
            double m = (double)l * l + (double)r * r; sum += m;
            float al = aw(&awL, l), ar = aw(&awR, r); asum += (double)al * al + (double)ar * ar;
            float p = fabsf(l) > fabsf(r) ? fabsf(l) : fabsf(r); if (p > peak) peak = p;
            float h = bq(&split, l); hf += (double)h * h; lf += (double)l * l;
        }
        double rms = sqrt(sum / (2.0 * frames)), arms = sqrt(asum / (2.0 * frames));
        double gain = perceptual(list[i].level) * 0.6f;
        printf("%-16s %8.1f %8.1f %8.3f %8.0f %9.1f\n", t->id, 20 * log10(rms + 1e-12), 20 * log10(arms + 1e-12), peak, 1000.0 * sqrt(hf / (lf + 1e-12)), 20 * log10(arms * gain + 1e-12));
    }
    return 0;
}

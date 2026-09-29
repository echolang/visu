/**
 * Phase functions shared by the sky, the aerial perspective and the height fog. Each takes
 * `mu`, the cosine between the view direction and the direction towards the light.
 */
#ifndef VISU_PHASE_GLSL
#define VISU_PHASE_GLSL

const float PHASE_PI = 3.14159265359;

/**
 * Rayleigh: symmetric, a little brighter along and against the light.
 */
float phase_rayleigh(float mu)
{
    return 3.0 / (16.0 * PHASE_PI) * (1.0 + mu * mu);
}

/**
 * Cornette-Shanks, the sky's Mie lobe with anisotropy `g`.
 */
float phase_mie(float g, float mu)
{
    float gg = g * g;
    float base = 1.0 + gg - 2.0 * g * mu;
    return 3.0 / (8.0 * PHASE_PI) * ((1.0 - gg) * (1.0 + mu * mu))
        / ((2.0 + gg) * base * sqrt(base));
}

/**
 * Henyey-Greenstein with anisotropy `g`: 1 / 4 pi when g is 0.
 */
float phase_hg(float g, float mu)
{
    float gg = g * g;
    float base = max(1.0 + gg - 2.0 * g * mu, 1e-4);
    return (1.0 - gg) / (4.0 * PHASE_PI * base * sqrt(base));
}

#endif

#ifndef GAMMA_CORR_GLSL
#define GAMMA_CORR_GLSL
/**
 * Gamma Correction
 * ----------------------------------------------------------------------------
 */

// override with -DVISU_DISPLAY_GAMMA=... at compile time
#ifndef VISU_DISPLAY_GAMMA
#define VISU_DISPLAY_GAMMA 2.2
#endif

/**
 * Apply gamma correction to a color
 */
vec3 gamma_correct(vec3 color)
{
    return pow(color, vec3(1.0 / VISU_DISPLAY_GAMMA));
}

/**
 * The linear value a display colour encodes; the inverse of gamma_correct.
 */
vec3 display_linear(vec3 display)
{
    return pow(max(display, vec3(0.0)), vec3(VISU_DISPLAY_GAMMA));
}

#endif

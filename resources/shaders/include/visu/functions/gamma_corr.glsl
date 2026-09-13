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

#endif

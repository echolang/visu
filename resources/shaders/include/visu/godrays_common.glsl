/**
 * Facts the light-shaft march, resolve and composite share. The march stores this distance
 * for sky texels and the composite looks sky pixels up with it; one define, so the two never
 * drift apart.
 */
#ifndef VISU_GODRAYS_COMMON_GLSL
#define VISU_GODRAYS_COMMON_GLSL

#define GODRAY_SKY_DEPTH 60000.0

#endif

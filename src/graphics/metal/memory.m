#import <Metal/Metal.h>
#include <stdint.h>

static id<MTLDevice> visu_mtl_sys(void)
{
    return MTLCreateSystemDefaultDevice();
}

uint64_t visu_mtl_current_allocated(void)
{
    id<MTLDevice> d = visu_mtl_sys();

    if (d == nil) {
        return 0;
    }

    return (uint64_t)d.currentAllocatedSize;
}

uint64_t visu_mtl_working_set(void)
{
    id<MTLDevice> d = visu_mtl_sys();

    if (d == nil) {
        return 0;
    }

    return (uint64_t)d.recommendedMaxWorkingSetSize;
}

int32_t visu_mtl_has_unified(void)
{
    id<MTLDevice> d = visu_mtl_sys();

    if (d == nil) {
        return 0;
    }

    return d.hasUnifiedMemory ? 1 : 0;
}

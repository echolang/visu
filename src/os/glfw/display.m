#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/message.h>
#import <objc/runtime.h>

int32_t visu_window_max_refresh(void *handle)
{
    if (handle == NULL) {
        return 0;
    }

    id obj = (__bridge id)handle;
    NSWindow *window = nil;

    if ([obj isKindOfClass:[NSWindow class]]) {
        window = (NSWindow *)obj;
    } else if ([obj isKindOfClass:[NSView class]]) {
        window = [(NSView *)obj window];
    }

    NSScreen *screen = window.screen;

    if (screen == nil) {
        screen = [NSScreen mainScreen];
    }

    if (screen == nil) {
        return 0;
    }

    if (@available(macOS 12.0, *)) {
        return (int32_t)screen.maximumFramesPerSecond;
    }

    return 0;
}

/**
 * Walk to the CAMetalLayer and toggle displaySyncEnabled. The Metal
 * arm owns its layer and drives this through libmetal instead; this
 * path exists for MoltenVK, where the layer belongs to the loader.
 */
static void visu_apply_sync_layer(id layer, int32_t enabled)
{
    if (layer == nil) {
        return;
    }

    if ([layer isKindOfClass:[CAMetalLayer class]]) {
        ((CAMetalLayer *)layer).displaySyncEnabled = enabled != 0;
    }

    SEL sublayers = sel_registerName("sublayers");

    if (![layer respondsToSelector:sublayers]) {
        return;
    }

    NSArray *subs = ((id (*)(id, SEL))objc_msgSend)(layer, sublayers);

    if (subs == nil) {
        return;
    }

    for (id sub in subs) {
        visu_apply_sync_layer(sub, enabled);
    }
}

void visu_set_display_sync(void *handle, int32_t enabled)
{
    if (handle == NULL) {
        return;
    }

    id obj = (__bridge id)handle;

    if ([obj isKindOfClass:[CAMetalLayer class]]) {
        visu_apply_sync_layer(obj, enabled);
        return;
    }

    id view = obj;
    SEL contentView = sel_registerName("contentView");

    if ([obj respondsToSelector:contentView]) {
        view = ((id (*)(id, SEL))objc_msgSend)(obj, contentView);
    }

    if (view == nil) {
        return;
    }

    SEL layerSel = sel_registerName("layer");

    if (![view respondsToSelector:layerSel]) {
        return;
    }

    id layer = ((id (*)(id, SEL))objc_msgSend)(view, layerSel);
    visu_apply_sync_layer(layer, enabled);
}

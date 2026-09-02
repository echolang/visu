#import <QuartzCore/CAMetalLayer.h>
#import <objc/message.h>
#import <objc/runtime.h>

void visu_set_display_sync(void *nsWindow, int32_t enabled)
{
    if (nsWindow == NULL) {
        return;
    }

    id window = (__bridge id)nsWindow;
    SEL contentView = sel_registerName("contentView");

    if (![window respondsToSelector:contentView]) {
        return;
    }

    id view = ((id (*)(id, SEL))objc_msgSend)(window, contentView);

    if (view == nil) {
        return;
    }

    SEL layerSel = sel_registerName("layer");
    id layer = ((id (*)(id, SEL))objc_msgSend)(view, layerSel);

    if (layer == nil || ![layer isKindOfClass:[CAMetalLayer class]]) {
        return;
    }

    ((CAMetalLayer *)layer).displaySyncEnabled = enabled != 0;
}

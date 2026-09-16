#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#include <stdint.h>
#include <string.h>

typedef void (*VisuIosResize)(int32_t, int32_t);
typedef void (*VisuIosTouch)(int32_t, int32_t, float, float, float);
typedef void (*VisuIosFn)(void);
typedef void (*VisuIosFocus)(int32_t);

static VisuIosResize gResize;
static VisuIosTouch gTouch;
static VisuIosFn gPause;
static VisuIosFn gResume;
static VisuIosFocus gFocus;
static NSMapTable<UITouch *, NSNumber *> *gTouchIds;
static NSMutableArray<NSNumber *> *gFreeTouchIds;
static int32_t gNextTouchId = 1;

enum {
    VISU_TOUCH_BEGAN = 0,
    VISU_TOUCH_MOVED = 1,
    VISU_TOUCH_ENDED = 2,
    VISU_TOUCH_CANCELLED = 3
};

@interface VisuMetalView : UIView
@end

@implementation VisuMetalView

+ (Class)layerClass
{
    return [CAMetalLayer class];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    if (gResize == NULL) {
        return;
    }

    CGFloat s = self.contentScaleFactor;
    int32_t w = (int32_t)(self.bounds.size.width * s);
    int32_t h = (int32_t)(self.bounds.size.height * s);
    if (w <= 0 || h <= 0) {
        return;
    }

    gResize(w, h);
}

static int32_t visu_ios_touch_id(UITouch *touch, int32_t phase)
{
    if (gTouchIds == nil) {
        gTouchIds = [NSMapTable weakToStrongObjectsMapTable];
        gFreeTouchIds = [NSMutableArray array];
    }

    NSNumber *existing = [gTouchIds objectForKey:touch];
    int32_t tid;
    if (existing != nil) {
        tid = existing.intValue;
    } else if (gFreeTouchIds.count > 0) {
        tid = gFreeTouchIds.lastObject.intValue;
        [gFreeTouchIds removeLastObject];
        [gTouchIds setObject:@(tid) forKey:touch];
    } else {
        tid = gNextTouchId++;
        [gTouchIds setObject:@(tid) forKey:touch];
    }

    if (phase == VISU_TOUCH_ENDED || phase == VISU_TOUCH_CANCELLED) {
        [gTouchIds removeObjectForKey:touch];
        [gFreeTouchIds addObject:@(tid)];
    }

    return tid;
}

- (void)emitTouches:(NSSet<UITouch *> *)touches phase:(int32_t)phase
{
    if (gTouch == NULL) {
        return;
    }

    for (UITouch *touch in touches) {
        CGPoint p = [touch locationInView:self];
        float force = 0.0f;
        if (touch.maximumPossibleForce > 0.0) {
            force = (float)(touch.force / touch.maximumPossibleForce);
        }
        int32_t tid = visu_ios_touch_id(touch, phase);
        gTouch(tid, phase, (float)p.x, (float)p.y, force);
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    (void)event;
    [self emitTouches:touches phase:VISU_TOUCH_BEGAN];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    (void)event;
    [self emitTouches:touches phase:VISU_TOUCH_MOVED];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    (void)event;
    [self emitTouches:touches phase:VISU_TOUCH_ENDED];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    (void)event;
    [self emitTouches:touches phase:VISU_TOUCH_CANCELLED];
}

@end

void visu_ios_set_hooks(
    VisuIosResize resize,
    VisuIosTouch touch,
    VisuIosFn pause,
    VisuIosFn resume,
    VisuIosFocus focus
)
{
    gResize = resize;
    gTouch = touch;
    gPause = pause;
    gResume = resume;
    gFocus = focus;
}

void visu_ios_notify_pause(void)
{
    if (gPause) {
        gPause();
    }
}

void visu_ios_notify_resume(void)
{
    if (gResume) {
        gResume();
    }
}

void visu_ios_notify_focus(int32_t gained)
{
    if (gFocus) {
        gFocus(gained);
    }
}

void *visu_ios_create_view(int32_t width, int32_t height)
{
    CGRect frame = CGRectMake(0, 0, (CGFloat)width, (CGFloat)height);
    UIWindow *key = UIApplication.sharedApplication.keyWindow;
    UIView *host = key.rootViewController.view;

    if (host == nil) {
        host = key;
    }

    VisuMetalView *view = [[VisuMetalView alloc] initWithFrame:host != nil ? host.bounds : frame];
    CGFloat scale = UIScreen.mainScreen.scale;
    view.contentScaleFactor = scale;
    ((CAMetalLayer *)view.layer).contentsScale = scale;
    view.multipleTouchEnabled = YES;
    view.opaque = YES;

    if (host != nil) {
        view.frame = host.bounds;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host addSubview:view];
    }

    return (__bridge_retained void *)view;
}

void visu_ios_destroy_view(void *view)
{
    if (view == NULL) {
        return;
    }

    VisuMetalView *v = (__bridge_transfer VisuMetalView *)view;
    [v removeFromSuperview];
}

void visu_ios_view_size(void *view, int32_t *w, int32_t *h)
{
    VisuMetalView *v = (__bridge VisuMetalView *)view;
    if (w) {
        *w = (int32_t)v.bounds.size.width;
    }
    if (h) {
        *h = (int32_t)v.bounds.size.height;
    }
}

void visu_ios_view_fb(void *view, int32_t *w, int32_t *h)
{
    VisuMetalView *v = (__bridge VisuMetalView *)view;
    CGFloat s = v.contentScaleFactor;
    if (w) {
        *w = (int32_t)(v.bounds.size.width * s);
    }
    if (h) {
        *h = (int32_t)(v.bounds.size.height * s);
    }
}

double visu_ios_view_scale(void *view)
{
    VisuMetalView *v = (__bridge VisuMetalView *)view;
    return (double)v.contentScaleFactor;
}

void visu_ios_safe_area(void *view, float *left, float *top, float *right, float *bottom)
{
    VisuMetalView *v = (__bridge VisuMetalView *)view;
    UIEdgeInsets in = v.safeAreaInsets;
    if (left) {
        *left = (float)in.left;
    }
    if (top) {
        *top = (float)in.top;
    }
    if (right) {
        *right = (float)in.right;
    }
    if (bottom) {
        *bottom = (float)in.bottom;
    }
}

int32_t visu_ios_documents_dir(uint8_t *buf, int32_t cap)
{
    if (buf == NULL || cap <= 1) {
        return 0;
    }

    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject;
    if (root == nil) {
        return 0;
    }

    const char *utf = root.UTF8String;
    size_t n = strlen(utf);
    if (n >= (size_t)cap) {
        n = (size_t)cap - 1;
    }
    memcpy(buf, utf, n);
    buf[n] = 0;
    return (int32_t)n;
}

int32_t visu_ios_resource_root(uint8_t *buf, int32_t cap)
{
    if (buf == NULL || cap <= 1) {
        return 0;
    }

    NSString *root = [NSBundle mainBundle].resourcePath;
    if (root == nil) {
        return 0;
    }

    const char *utf = root.UTF8String;
    size_t n = strlen(utf);
    if (n >= (size_t)cap) {
        n = (size_t)cap - 1;
    }
    memcpy(buf, utf, n);
    buf[n] = 0;
    return (int32_t)n;
}

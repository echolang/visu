#import <UIKit/UIKit.h>
#import <QuartzCore/CADisplayLink.h>

typedef void (*VisuIosFn)(void);

static VisuIosFn gStart;
static VisuIosFn gTick;
static VisuIosFn gStop;

void visu_ios_notify_pause(void);
void visu_ios_notify_resume(void);
void visu_ios_notify_focus(int32_t gained);

@class VisuAppDelegate;
static VisuAppDelegate *gApp;

@interface VisuAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic) UIWindow *window;
@property (nonatomic) CADisplayLink *link;
@end

@implementation VisuAppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts
{
    (void)app;
    (void)opts;

    gApp = self;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *root = [[UIViewController alloc] init];
    root.view.backgroundColor = UIColor.blackColor;
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];

    if (gStart) {
        gStart();
    }

    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    return YES;
}

- (void)frame:(CADisplayLink *)link
{
    (void)link;
    if (gTick) {
        gTick();
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)app
{
    (void)app;
    visu_ios_notify_focus(1);
}

- (void)applicationWillResignActive:(UIApplication *)app
{
    (void)app;
    visu_ios_notify_focus(0);
}

- (void)applicationDidEnterBackground:(UIApplication *)app
{
    (void)app;
    self.link.paused = YES;
    visu_ios_notify_pause();
}

- (void)applicationWillEnterForeground:(UIApplication *)app
{
    (void)app;
    visu_ios_notify_resume();
    self.link.paused = NO;
}

- (void)applicationWillTerminate:(UIApplication *)app
{
    (void)app;
    [self.link invalidate];
    self.link = nil;
    if (gStop) {
        gStop();
    }
}

@end

int visu_ios_boot(VisuIosFn start, VisuIosFn tick, VisuIosFn stop)
{
    gStart = start;
    gTick = tick;
    gStop = stop;

    static char name[] = "visu";
    char *argv[] = { name, NULL };
    return UIApplicationMain(1, argv, nil, NSStringFromClass([VisuAppDelegate class]));
}

void visu_ios_request_stop(void)
{
    [gApp.link invalidate];
    gApp.link = nil;
}

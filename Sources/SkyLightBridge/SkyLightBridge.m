#import "SkyLightBridge.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>

// Declaring the designated initializers lets ARC handle alloc/init ownership.
// The actual classes are looked up by name and are never linked directly.
@protocol FlickMoveOperation
- (instancetype)initWithWindows:(NSArray<NSNumber *> *)windows spaceID:(uint64_t)space;
- (void)performWithWMBridgeDelegate;
@end

@protocol FlickActivateOperation
- (instancetype)initWithDisplayIdentifier:(NSString *)display spaceID:(uint64_t)space;
- (id)performWithWMBridgeDelegate;
@end

static int (*mainConnection)(void);
static CFArrayRef (*copyDisplays)(int);
static CFArrayRef (*copyWindowSpaces)(int, int, CFArrayRef);
static AXError (*getWindowID)(AXUIElementRef, CGWindowID *);
static Class moveClass;
static Class activateClass;

bool FlickSkyLightAvailable(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                               RTLD_LAZY | RTLD_LOCAL);
        if (!library)
            return;
        mainConnection = dlsym(library, "SLSMainConnectionID");
        copyDisplays = dlsym(library, "SLSCopyManagedDisplaySpaces");
        copyWindowSpaces = dlsym(library, "SLSCopySpacesForWindows");
        getWindowID = dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow");
        moveClass = NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation");
        activateClass = NSClassFromString(@"SLSBridgedManagedDisplaySetCurrentSpaceOperation");
    });
    return mainConnection && copyDisplays && copyWindowSpaces && getWindowID &&
           [moveClass instancesRespondToSelector:@selector(initWithWindows:spaceID:)] &&
           [moveClass instancesRespondToSelector:@selector(performWithWMBridgeDelegate)] &&
           [activateClass instancesRespondToSelector:@selector(initWithDisplayIdentifier:
                                                                                 spaceID:)] &&
           [activateClass instancesRespondToSelector:@selector(performWithWMBridgeDelegate)];
}

CFArrayRef FlickCopyDisplays(void) {
    return FlickSkyLightAvailable() ? copyDisplays(mainConnection()) : NULL;
}

CFArrayRef FlickCopyWindowSpaces(CGWindowID window) {
    if (!FlickSkyLightAvailable())
        return NULL;
    return copyWindowSpaces(mainConnection(), 0x7, (__bridge CFArrayRef) @[ @(window) ]);
}

CGWindowID FlickWindowID(AXUIElementRef window) {
    CGWindowID identifier = 0;
    if (FlickSkyLightAvailable() && getWindowID(window, &identifier) == kAXErrorSuccess)
        return identifier;
    return 0;
}

bool FlickMoveWindow(CGWindowID window, uint64_t space) {
    if (!FlickSkyLightAvailable())
        return false;
    @try {
        id<FlickMoveOperation> operation =
            [(id<FlickMoveOperation>)[moveClass alloc] initWithWindows:@[ @(window) ]
                                                               spaceID:space];
        if (!operation)
            return false;
        [operation performWithWMBridgeDelegate];
        return true;
    } @catch (NSException *exception) {
        return false;
    }
}

bool FlickActivateSpace(CFStringRef display, uint64_t space) {
    if (!FlickSkyLightAvailable())
        return false;
    @try {
        id<FlickActivateOperation> operation = [(id<FlickActivateOperation>)[activateClass alloc]
            initWithDisplayIdentifier:(__bridge NSString *)display
                              spaceID:space];
        if (!operation)
            return false;
        [operation performWithWMBridgeDelegate];
        return true;
    } @catch (NSException *exception) {
        return false;
    }
}

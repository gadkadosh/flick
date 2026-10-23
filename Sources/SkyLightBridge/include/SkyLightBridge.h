#import <ApplicationServices/ApplicationServices.h>

/// Every private symbol is resolved at runtime; an unavailable backend fails
/// before moving anything instead of falling back to synthetic dragging.
bool FlickSkyLightAvailable(void);
CFArrayRef _Nullable FlickCopyDisplays(void) CF_RETURNS_RETAINED;
CFArrayRef _Nullable FlickCopyWindowSpaces(CGWindowID window) CF_RETURNS_RETAINED;
CGWindowID FlickWindowID(AXUIElementRef _Nonnull window);
bool FlickMoveWindow(CGWindowID window, uint64_t space);
bool FlickActivateSpace(CFStringRef _Nonnull display, uint64_t space);

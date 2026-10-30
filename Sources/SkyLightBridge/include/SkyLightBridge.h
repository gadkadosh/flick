#import <ApplicationServices/ApplicationServices.h>

/// Every private symbol is resolved at runtime; an unavailable backend fails
/// before moving anything instead of falling back to synthetic dragging.
bool FlickSkyLightAvailable(void);
CFArrayRef _Nullable FlickCopyDisplays(void) CF_RETURNS_RETAINED;
/// The keyboard-active display, not the display containing the pointer.
CFStringRef _Nullable FlickCopyActiveDisplay(void) CF_RETURNS_RETAINED;
CFArrayRef _Nullable FlickCopyWindowSpaces(CGWindowID window) CF_RETURNS_RETAINED;
CFArrayRef _Nullable FlickCopyVisibleSpaces(void) CF_RETURNS_RETAINED;
CGWindowID FlickWindowID(AXUIElementRef _Nonnull window);
bool FlickMoveWindow(CGWindowID window, uint64_t space);
/// Show the destination and hide only other managed Spaces on this display.
bool FlickActivateSpace(CFStringRef _Nonnull display, uint64_t space,
                        CFArrayRef _Nonnull spacesToHide);

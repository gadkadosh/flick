# Window-switcher verification

Automated tests cover display/Space filtering, recent-window ordering, keyboard-event routing, cycling, quick release during discovery, cancellation, and focus failures. They do not prove macOS window enumeration, actual focus, permissions, or overlay appearance.

Run app/UI checks inside a prepared Tart guest with a logged-in desktop, remote command access, and Accessibility permission for the installed Flick build. Coordinate any host or physical-display checks first. Do not grant Screen Recording just to make enumeration work: the icon/title switcher must work without it.

## Guest checks

1. Install `build/Flick.app` at a stable path. With Accessibility denied, verify the menu reports window switching unavailable and normal typing/⌘Tab still work. Grant Accessibility, reopen the menu, and verify recovery.
2. Open two windows in one app and another window in a second app. Hold ⌥Tab: the overlay must not activate Flick or change the frontmost window. Check icons, titles, selection contrast, scrolling, and long titles.
3. Cycle forward and backward, release Option, and verify the exact selected window becomes focused. Quick ⌥Tab should toggle between the last two eligible windows, including windows of the same app.
4. Press Escape, type another key, or click while cycling. The overlay must close without selecting a window; unrelated input must reach the original app. Release Option before releasing Tab and check no stray Tab reaches the app.
5. Minimize a window, hide an app, open a dialog, and move a window to another Space. Confirm none of those ineligible windows appears. A fully covered but non-minimized ordinary window should remain eligible.
6. Close or minimize the selected window, or change Spaces, before releasing Option. Flick must not switch desktops or claim successful focus on an invalid target. Repeat while an app is unresponsive; typing/clicking must cancel delayed discovery.
7. Enable Secure Keyboard Entry (for example, from Terminal's menu). Flick must not leave a stuck overlay or make a delayed selection. Disable secure entry and verify switching recovers.
8. Toggle **Window Switcher (⌥Tab)** off and relaunch. Verify the setting persists and the shortcut no longer opens Flick. Re-enable and confirm it works. Check Space shortcuts still work and cannot start during window selection.

## Coordinated multi-display checks

- Put windows of the same app on two displays. Start from each display in turn: only its eligible windows should appear, and selection must focus the exact window without moving anything or switching another display's Space.
- Move the pointer to the other display without changing window focus. The focused window's display should still win. With no accessible focused window, check the active menu-bar-display fallback.
- Test displays left of and above the primary display, differing scale factors, and a spanning window with most of its area on the display opposite its origin.
- Change the active Space on only one display. Each list must use that display's currently visible Space. Disconnect a display during selection: cancel/report the changed layout rather than selecting elsewhere.
- Check fullscreen, Stage Manager, and “Displays have separate Spaces” disabled explicitly before expanding their documented support.

Record the macOS version, display arrangement/scale factors, Space configuration, affected applications, and Last Result for failures. Capture overlay screenshots and retrieve them from the guest for visual inspection.

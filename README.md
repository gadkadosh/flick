# Flick

Switch macOS Spaces without animation, move windows between desktops, and switch windows on just the current display. A small menu-bar app:

| Shortcut | Action |
| --- | --- |
| **⌥[ / ⌥]** | Switch to the previous / next desktop |
| **⌥⇧[ / ⌥⇧]** | Move the focused window to the previous / next desktop and follow it |
| **⌥Tab / ⌥⇧Tab** | Cycle forward / backward through windows on the current display |

No external dependencies, screen capture, SIP changes, telemetry, or network access.

**Experimental:** Flick uses undocumented macOS APIs. Switching and window moves have been validated on one physical display on macOS 27.0.1 with SIP enabled. macOS updates may break compatibility.

## Build and install

Requires Swift 6 / Xcode 16+. The app targets macOS 13+, but older releases have not been verified.

1. Clone or download this repository, then run `make` from its directory.
2. Copy `build/Flick.app` to `/Applications` (or `~/Applications`), then open the installed copy. Do this **before** granting permission or enabling launch at login.
3. To move or switch windows, choose **Grant Accessibility…** in Flick's menu, click **Open System Settings** in the macOS prompt, and enable Flick under **Privacy & Security → Accessibility**. Use `+` to add the app if needed. Switching desktops alone does not need this permission.

The app is locally signed, not notarized. Keep it in a stable location; rebuilding may require removing and re-adding its Accessibility entry.

## Use

Use the shortcuts above, or choose alternatives under **Previous / Next Desktop** and **Move Window** in the menu.

**Go to Desktop** optionally enables **⌃1–9**, **⌥1–9**, or **⌃⌥1–9** (off by default). Numbers match Mission Control and Flick’s menu-bar indicator: ordinary desktops are numbered across displays; fullscreen/Split View Spaces are not counted. Jumping goes directly to the selected desktop without moving windows. A missing desktop reports an error; selecting an already-visible desktop does nothing. Jumps cannot start while another Space operation is running.

### Window switcher

Hold **Option** and press **Tab** to cycle through individual windows; add **Shift** to reverse. Release Option to select, or press **Escape** to cancel. macOS’s **⌘Tab** is unchanged. Disable this feature using **Window Switcher (⌥Tab)** in Flick’s menu.

The display is captured from the focused window when switching starts, falling back to the active menu-bar display when there is no accessible focused window. Windows spanning displays belong to the one containing the largest portion of their area. Only ordinary, on-screen windows on that display’s visible Space are included—not minimized windows, hidden apps, dialogs, fullscreen windows, or inaccessible windows. Flick does not move windows or request desktop changes when selecting one.

Windows are ordered by recent focus observed while Flick is running; windows not yet observed use front-to-back order. The list stays fixed while cycling. A quick ⌥Tab toggles between the last two eligible windows. Typing, clicking, Secure Keyboard Entry, or losing keyboard capture cancels a pending selection. Discovery skips unresponsive apps and may take longer when several apps are slow to respond.

The switcher needs Accessibility but does not capture window thumbnails or require Screen Recording. After granting permission, reopen Flick’s menu to retry. Other tools binding ⌥Tab can conflict; Flick cannot guarantee exclusive ownership of an event-tap shortcut.

Bracket and number shortcuts use physical US-layout key positions, not the numeric keypad. Enabling Option+number takes those combinations away from typing symbols in other apps.

If shortcuts don’t work or still animate, choose another shortcut preset or open **Help → Keyboard Shortcuts…** in Flick’s menu, select **Mission Control** in the sidebar, and disable or reassign conflicting shortcuts. Check **Help → Last Result…** in Flick’s menu for errors.

## Limitations

- Cannot move fullscreen/Split View windows, dialogs, or windows assigned to multiple or all Spaces.
- Window moves use the window's display; previous/next switching uses the active menu-bar display, not the pointer. Numbered jumps use the display containing that desktop. Physical multi-display setups, shared Spaces, and Stage Manager are not yet validated.
- The window switcher has automated coverage but has not yet been verified in a logged-in desktop or on physical multi-display hardware. Shared-Space configurations that cannot be matched to display identifiers are rejected.

Flick reports failures rather than falling back to simulated dragging. If a window moves but Flick cannot follow it, it does not automatically move the window back.

## Development

```sh
make test
make
build/Flick.app/Contents/MacOS/Flick --diagnose
```

Quit Flick before running diagnostics to avoid shortcut conflicts with the running app. Changes to Space operations also need manual testing; automated tests don’t exercise the private macOS APIs.

For bug reports, include your macOS version, affected app, display/Space setup, shortcut preset, and **Last Result…** message.

## License

[MIT](LICENSE) © 2026 Gad Kadosh.

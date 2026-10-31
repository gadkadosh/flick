# Flick

Switch macOS Spaces without animation. A small menu-bar app for switching desktops and moving windows:

| Shortcut | Action |
| --- | --- |
| **⌥[ / ⌥]** | Switch to the previous / next desktop |
| **⌥⇧[ / ⌥⇧]** | Move the focused window to the previous / next desktop and follow it |

No external dependencies, screen capture, SIP changes, telemetry, or network access.

**Experimental:** Flick uses undocumented macOS APIs. Switching and window moves have only been validated on one display on macOS 27.0.1 with SIP enabled. macOS updates may break compatibility.

## Build and install

Requires Swift 6 / Xcode 16+. The app targets macOS 13+, but older releases have not been verified.

1. Clone or download this repository, then run `make` from its directory.
2. Copy `build/Flick.app` to `/Applications` (or `~/Applications`), then open the installed copy. Do this **before** granting permission or enabling launch at login.
3. To move windows, choose **Grant Accessibility…** in Flick's menu, click **Open System Settings** in the macOS prompt, and enable Flick under **Privacy & Security → Accessibility**. Use `+` to add the app if needed. Switching desktops alone does not need this permission.

The app is locally signed, not notarized. Keep it in a stable location; rebuilding may require removing and re-adding its Accessibility entry.

## Use

Use the shortcuts above, or choose alternatives under **Previous / Next Desktop** and **Move Window** in the menu.

**Go to Desktop** optionally enables **⌃1–9**, **⌥1–9**, or **⌃⌥1–9** (off by default). Numbers match Mission Control and Flick’s menu-bar indicator: ordinary desktops are numbered across displays; fullscreen/Split View Spaces are not counted. Jumping goes directly to the selected desktop without moving windows. A missing desktop reports an error; selecting an already-visible desktop does nothing. Jumps cannot start while another Space operation is running.

Bracket and number shortcuts use physical US-layout key positions, not the numeric keypad. Enabling Option+number takes those combinations away from typing symbols in other apps.

If shortcuts don’t work or still animate, choose another shortcut preset or disable conflicting Mission Control shortcuts in System Settings. Check **Help → Last Result…** in Flick’s menu for errors.

## Limitations

- Cannot move fullscreen/Split View windows, dialogs, or windows assigned to multiple or all Spaces.
- Window moves use the window's display; previous/next switching uses the active menu-bar display, not the pointer. Numbered jumps use the display containing that desktop. Multiple displays, shared Spaces, and Stage Manager are not yet validated.
- Switching and moving cannot run together. Window moves cannot start during a mouse drag or while Secure Keyboard Entry blocks keyboard observation.

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

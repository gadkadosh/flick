# Flick

Switch macOS Spaces without animation. A small menu-bar app with two actions:

| Shortcut | Action |
| --- | --- |
| **⌥[ / ⌥]** | Switch to the previous / next desktop |
| **⌥⇧[ / ⌥⇧]** | Move the focused window to the previous / next desktop and follow it |

No external dependencies, screen capture, SIP changes, telemetry, or network access.

**Experimental:** Flick uses undocumented macOS APIs. Switching and window moves have only been validated on one display on macOS 27.0.1 with SIP enabled. macOS updates may break compatibility.

## Build and install

Requires Swift 6 / Xcode 16+. The app targets macOS 13+, but older releases have not been verified.

1. Clone or download this repository, then run:

   ```sh
   make
   ```

2. Copy `build/Flick.app` to `/Applications` (or `~/Applications`), then open the installed copy. Do this **before** granting permission or enabling launch at login.
3. To move windows, choose **Grant Accessibility…** in Flick's menu, click **Open System Settings** in the macOS prompt, and enable Flick under **Privacy & Security → Accessibility**. Use `+` to add the app if needed. Switching desktops alone does not need this permission.

The app is locally signed, not notarized. Keep it in a stable location; rebuilding may require removing and re-adding its Accessibility entry.

## Use

Use the shortcuts above, or choose alternatives under **Switch shortcuts** and **Move shortcuts** in the menu. Bracket shortcuts use physical US-layout bracket key positions.

If an action fails, check **Last result…** in the menu. If shortcuts do not fire, switch twice, or still animate, choose another preset or disable matching shortcuts under **System Settings → Keyboard → Keyboard Shortcuts → Mission Control**, then reopen Flick's menu. A **Possible system shortcut overlap…** warning alone does not mean anything is broken.

## Limitations

- Works with adjacent ordinary desktops. It does not wrap, create desktops, or skip fullscreen/Split View Spaces.
- Cannot move fullscreen/Split View windows, dialogs, or windows assigned to multiple or all Spaces.
- Window moves use the window's display; switching uses the active menu-bar display, not the pointer. Multiple displays, shared Spaces, and Stage Manager are not yet validated.
- Switching and moving cannot run together. Window moves cannot start during a mouse drag or while Secure Keyboard Entry blocks keyboard observation.

Flick reports failures rather than falling back to simulated dragging. If a window moves but Flick cannot follow it, it does not automatically move the window back.

## Development

```sh
make test
make
build/Flick.app/Contents/MacOS/Flick --diagnose
```

Quit Flick before running diagnostics. Automated tests do not exercise the private APIs; changes to Space operations also need live checks for switching, moving, repeated presses, boundaries, and interruptions.

For bug reports, include your macOS version, affected app, display/Space setup, shortcut preset, and **Last result…** message.

## License

[MIT](LICENSE) © 2026 Gad Kadosh.

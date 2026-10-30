# Flick

Switch macOS Spaces without animation. Flick is a small menu-bar app that jumps to an adjacent desktop, or moves the focused window and follows it.

- **⌥[ / ⌥]**: switch to the previous / next Space without moving windows
- **⌥⇧[ / ⌥⇧]**: move the focused window to the previous / next Space and follow it
- Rapid presses queue actions; independent switch/move presets and launch at login are available in the menu
- No external dependencies, screen capture, SIP changes, telemetry, or network access

**Experimental:** Flick uses undocumented macOS APIs. Switching and window moves have been validated only on one display on macOS 27.0.1 with SIP enabled. macOS updates may break them. Flick reports failures rather than falling back to simulated dragging.

## Build and install

Flick is distributed as source and requires Swift 6 / Xcode 16+ to build. It can launch on macOS 13+, but Space switching and window moves are not verified on older releases.

1. Clone or download this repository, then run from its directory:

   ```sh
   make
   ```

2. Quit any running Flick instance. Copy `build/Flick.app` to `/Applications` (or `~/Applications`) **before** granting permission or enabling launch at login, then open the installed copy.
3. For window moves, choose **Grant Accessibility…** in Flick's menu and enable Flick under **System Settings → Privacy & Security → Accessibility**. If needed, use `+` to add the app. Standalone Space switching does not require Accessibility.
4. Choose **Switch shortcuts** and **Move shortcuts** in Flick's menu if you prefer another key family. If a shortcut does not fire reliably, disable or reassign matching shortcuts under **System Settings → Keyboard → Keyboard Shortcuts → Mission Control**, then reopen Flick's menu to retry registration.

The build is locally signed for your Mac, not notarized. Keep the app in a stable location; rebuilding may require removing and re-adding its Accessibility entry. To preserve signing across rebuilds, set `FLICK_SIGN_IDENTITY` to an installed signing identity.

## Using Flick

By default, press **⌥[ / ⌥]** to switch desktops, or focus an ordinary window in another app and press **⌥⇧[ / ⌥⇧]** to move it and follow. Uncheck **Enable Space switching** in the menu if you only want window moving. The read-only shortcut summary then shows “(off)”.

Both shortcut menus offer the same families, with Shift added for moving. Selections are independent and saved between launches:

| Preset | Switch Space | Move window + follow |
| --- | --- | --- |
| Control + arrows | ⌃← / ⌃→ | ⌃⇧← / ⌃⇧→ |
| Option + brackets (default) | ⌥[ / ⌥] | ⌥⇧[ / ⌥⇧] |
| Control–Option + brackets | ⌃⌥[ / ⌃⌥] | ⌃⌥⇧[ / ⌃⌥⇧] |

macOS's own switching default is Control + arrows. Unrecognized saved presets fall back to Option + brackets.

Tap repeatedly to queue up to eight waiting steps. Queued moves keep the same window; you can keep the modifiers held, but release the shortcut key between presses. Avoid switching apps or desktops during a sequence. Clicking or typing during queued window moves cancels the remaining steps; the current step finishes without stealing focus back.

Check **Last result…** or the menu-bar tooltip if an action fails. If a window moves but Flick cannot follow it, the result says so; Flick does not automatically move it back.

### Shortcut conflicts

**Possible system shortcut overlap…** means macOS lists the same keys in its preferences—not that Flick cannot use them. macOS also stores hidden Shift variants of Mission Control shortcuts, which are not shown separately in System Settings. If Flick works reliably, no action is needed.

Overlaps are advisory: Flick attempts registration, and reports actual registration failures separately. If keys do not fire, switch twice, or show an animation, choose another Flick preset or disable/reassign matching Mission Control shortcuts, then reopen Flick's menu. Successful registration alone does not prove macOS will leave the keys to Flick. Flick does not change your keyboard or animation settings.

Bracket shortcuts use physical US-layout bracket key positions. Custom shortcuts and layout-aware key selection are not supported.

## Limitations

- Flick works with adjacent ordinary desktops. It does not wrap, create Spaces, or skip fullscreen/Split View Spaces. A desktop boundary or failure stops queued actions.
- Fullscreen/Split View windows, dialogs, and windows assigned to multiple or all Spaces cannot be moved.
- Window moves use the window's display; standalone switching uses the active menu-bar display, not the pointer's display. Multiple displays, shared Spaces, and Stage Manager still need live validation.
- Window moves and standalone switching cannot run together. Finish one sequence before starting the other.
- Window moves cannot start during a mouse drag or while Secure Keyboard Entry prevents keyboard observation. If secure entry starts during a sequence, the current step finishes, but queued moves and refocusing are skipped. Flick does not change Secure Keyboard Entry settings.

## Development and contributing

```sh
make test
make
build/Flick.app/Contents/MacOS/Flick --diagnose
build/Flick.app/Contents/MacOS/Flick --smoke-test
```

Quit any running Flick instance before diagnostics or the smoke test. `--diagnose` checks settings, permissions, API availability, and shortcuts without moving windows or switching desktops. `--smoke-test` briefly launches with Space operations disabled. Terminal-reported Accessibility permission may differ from permission for the installed app.

Automated tests do not execute the private APIs or prove macOS compatibility. For shortcut changes, check both submenus, independent persistence, switching on/off, and overlap warnings separately from registration errors. With matching Mission Control bindings enabled, verify one switch per press without animation; repeat after disabling those system bindings.

Changes to switching or window moves also need live checks: use adjacent ordinary desktops with one display and Stage Manager off; verify switching, moving, rapid presses, desktop boundaries, fullscreen rejection, and interruption handling without cursor jumps, resizing, or slide animations.

Issues and small, focused pull requests are welcome. For failures, include your macOS version, affected app, display/Space setup, shortcut preset, and **Last result…** message. Run the checks above before submitting code.

## License

[MIT](LICENSE) © 2026 Gad Kadosh.

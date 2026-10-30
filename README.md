# Flick

A small macOS menu-bar app that switches adjacent desktop Spaces instantly, or moves the focused window and follows it.

- **⌃← / ⌃→**: switch to the previous / next Space without moving windows
- **⌥⇧[ / ⌥⇧]**: move the focused window to the previous / next Space and follow it
- Rapid presses queue the same action, with up to eight waiting steps
- Alternative shortcut presets and optional launch at login
- Direct moves and desktop switches, without dragging, moving the cursor, resizing the window, or a slide animation
- No external dependencies, screen capture, SIP changes, telemetry, or network access

**Experimental:** Flick uses undocumented SkyLight APIs, resolved at runtime. Direct moves and standalone switching have been validated on one display on macOS 27.0.1 with SIP enabled. macOS updates may change or remove these operations. Flick reports unavailable or unconfirmed moves and has no simulated-drag fallback.

## Build and install

Requires Swift 6 / Xcode 16+ to build and compatible macOS Space operations to switch desktops or move windows. The executable can launch on macOS 13+, but that deployment target does not guarantee that the private operations work on older macOS releases. Live moves are currently validated only on macOS 27.0.1.

Flick is currently distributed as source. Clone or download this repository, then run these commands from its directory:

```sh
./scripts/build-app.sh
open build/Flick.app
```

The script produces an ad-hoc-signed local app, not a notarized distribution build. It prefers `/Applications/Xcode.app` when available without changing `xcode-select`; you can override `DEVELOPER_DIR`.

The app is built for your Mac's architecture; the script does not produce a universal binary. Private API use makes this build unsuitable for Mac App Store distribution.

To install, quit Flick and copy it to `/Applications` (or `~/Applications`) **before** granting permission or enabling launch at login. Launch the installed copy, not both copies.

1. For window moves, choose **Grant Accessibility…** in Flick's menu and enable Flick under **System Settings → Privacy & Security → Accessibility**. If needed, use `+` to add the app. Standalone Space switching does not require Accessibility.
2. To use **⌃← / ⌃→**, disable or reassign any matching shortcuts under **System Settings → Keyboard → Keyboard Shortcuts → Mission Control**, then reopen Flick's menu to retry registration. macOS normally reserves these keys by default. Flick warns rather than registering conflicting switch shortcuts; window moves remain available.
3. Press **⌃← / ⌃→** to switch desktops, or focus an ordinary window in another app and press a window-move shortcut. Avoid switching apps or desktops during a sequence.

Flick reads system shortcuts only to detect conflicts; it does not send them or change your animation or keyboard settings. Turn off **Switch Spaces: ⌃← / ⌃→** in Flick's menu if you only want window moving.

Keep the app in a stable location. Rebuilding an ad-hoc-signed app may require removing and re-adding its Accessibility entry. For stable signing across rebuilds, set `FLICK_SIGN_IDENTITY` to an installed signing identity.

### Shortcut conflicts

macOS may also reserve Flick's default shortcuts, including implicit Shift variants of Mission Control shortcuts. Successful registration does not guarantee macOS will route the keys to Flick. The menu warns about known overlaps.

If the default does not fire, choose **⌃⌥[ / ⌃⌥]** or **⌃⌥⇧[ / ⌃⌥⇧]** under **Move shortcuts**. A preset identical to an actual Space-switching shortcut is rejected.

Bracket shortcuts use physical US-layout bracket key positions. Arbitrary shortcut recording and layout-aware key selection are not supported. Repeated key-down events are ignored until the shortcut key is released; modifiers can stay held between presses.

## Behavior and limitations

### Switching Spaces

Standalone switching reads macOS's active menu-bar display, not the display under the pointer or the display of a captured window. It shows the adjacent ordinary desktop, hides the other managed Spaces on that display, and confirms both the current desktop and its exclusive visibility. No focused window is required, and Flick does not move, raise, or explicitly refocus windows. macOS handles the destination's focus.

Queued switches retain the same display and stop if the active display changes, an operation fails, or a desktop boundary is reached. Window moves and standalone switching cannot run together; a different kind of action is rejected while a sequence is running. Flick does not wrap, create Spaces, or skip fullscreen/Split View Spaces. An unidentified display fails without guessing another display. Multi-display and shared-Space configurations still need live validation.

### Moving windows

Flick captures the focused window through Accessibility and identifies its current desktop and the adjacent Space on the same display. It requests a direct move, waits until that window belongs exclusively to the destination, and then switches the display to that desktop without a slide animation. It confirms the active desktop and that no other managed Space on its display remains visible before refocusing the captured window. Window size, position, and cursor coordinates are never written.

The move result appears under **Last result…** and in the menu-bar tooltip. A successful result confirms both destination membership and the destination desktop. An unconfirmed move does not trigger a desktop-switch request. If the window moves but following fails, Flick reports that distinction; it does not automatically navigate back or replay queued steps against another window.

Queued requests retain the same captured window. Focus changes detected between steps, failed operations, and desktop boundaries stop the sequence and discard remaining requests. During a sequence, any mouse click or key press other than Flick's configured move shortcuts also discards queued requests. Modifier changes and pointer movement are allowed. Flick observes this input without blocking it; the in-flight move-and-follow finishes, but Flick skips refocusing after an interruption. Flick does not wrap, create Spaces, or skip a fullscreen Space between two desktops.

Fullscreen/Split View windows, dialogs, and windows belonging to multiple or all Spaces are rejected. An adjacent fullscreen/Split View destination is also rejected. Custom title bars do not require special handling. Stage Manager and multiple displays are not yet validated with live moves; destination selection uses the captured window's display rather than the cursor's display.

Flick refuses to start a window move during a user mouse drag or while Secure Keyboard Entry prevents keyboard observation. If secure entry is detected during a move sequence, the current move-and-follow finishes, but queued requests and refocusing are skipped—even if secure entry ends before the move finishes. Flick does not change Secure Keyboard Entry settings. Quitting discards queued requests and lets confirmation of the current bounded Space operation finish before exiting. No synthetic mouse button is held and no cursor or window-frame cleanup is needed.

### Manual validation

Start with one display, Stage Manager off, and at least two adjacent ordinary desktop Spaces.

1. Switch right and back with **⌃→ / ⌃←**, including an empty destination and consecutive empty desktops. Confirm the outgoing windows disappear, the wallpaper repaints, only one menu bar is visible, no slide animation or cursor/window movement occurs, and macOS restores useful focus. Repeat from the desktop with no ordinary window focused. With three Spaces, test rapid presses and opposite directions; check the boundary. Check that a conflicting Mission Control shortcut disables only Flick's switch shortcuts, and that reopening Flick's menu after resolving it enables them.
2. Move Zen right and back left. Confirm its address field stays closed, both the window and desktop move, and there is no slide animation or cursor jump.
3. Repeat with a filled/tiled Ghostty window. Check that its size, position, terminal grid, and focus remain unchanged after each move.
4. Repeat while keeping the shortcut modifiers held.
5. With three adjacent Spaces, tap right twice quickly. Confirm the same window travels two Spaces. Also test queued opposite directions.
6. Test the desktop boundary: the window and desktop should stay put, and queued steps should be discarded.
7. Test a fullscreen window and fullscreen destination (both should reject), switching focus during a queued sequence, and quitting during a move.
8. With Secure Keyboard Entry active, confirm that a move is refused without moving the window or desktop. If it becomes active during a sequence, confirm only the in-flight step finishes, without refocusing or replaying queued requests.

A successful build does not replace these live checks. CI tests move/switch ordering and failure handling without invoking the private operations.

## Development

```sh
./scripts/test.sh
./scripts/build-app.sh
build/Flick.app/Contents/MacOS/Flick --diagnose
build/Flick.app/Contents/MacOS/Flick --smoke-test
```

The unit tests cover Space layout parsing and adjacency, confirmed move-and-follow ordering, standalone switching without touching windows, display selection, silent API failures, cancellation, shortcut conflicts (including macOS defaults) and presets, hotkey repeat handling, queue ordering/capacity/closure, and input interruption or lost keyboard observation before refocusing or replaying queued moves. They do not execute the private APIs or prove macOS compatibility.

`--diagnose` reads settings, permission status, runtime API availability, and the active display/layout match, and briefly registers/unregisters hotkeys without moving windows or switching desktops. Runtime symbol availability is not proof that macOS will apply a move. `--smoke-test` briefly starts the menu-bar app with all Space callbacks disabled and exits. Quit any running Flick instance before either check so its registrations do not interfere. Accessibility permission reported from a terminal-run binary may differ from the app launched through Finder/LaunchServices.

### Code map

The main path is **hotkey → app delegate → window mover or Space switcher → confirmed operation → SkyLight bridge**.

- [`FlickMain.swift`](Sources/Flick/FlickMain.swift): starts the app or runs diagnostics.
- [`AppDelegate.swift`](Sources/Flick/AppDelegate.swift): owns the menu, preferences, hotkeys, and asynchronous move task.
- [`HotKeys.swift`](Sources/Flick/HotKeys.swift): registers global shortcuts and reports distinct presses.
- [`WindowMover.swift`](Sources/Flick/WindowMover.swift): captures and refocuses one window for the whole queued move sequence.
- [`WindowMoveInputMonitor.swift`](Sources/Flick/WindowMoveInputMonitor.swift): passively observes input during a move sequence so user intervention cannot be hidden by refocusing.
- [`SpaceSwitcher.swift`](Sources/Flick/SpaceSwitcher.swift): captures macOS's active display for a queued standalone-switch sequence.
- [`SkyLight.swift`](Sources/Flick/SkyLight.swift): adapts the bridge to the core logic and reads the active display.
- [`Spaces.swift`](Sources/FlickCore/Spaces.swift): desktop layout parsing and adjacent destination selection.
- [`SpaceMove.swift`](Sources/FlickCore/SpaceMove.swift): dispatches a move, verifies membership, follows, and verifies the desktop.
- [`SpaceSwitch.swift`](Sources/FlickCore/SpaceSwitch.swift): switches desktops without touching windows; shares bounded confirmation polling with moves.
- [`SkyLightBridge.m`](Sources/SkyLightBridge/SkyLightBridge.m): isolates private C symbols and Objective-C operations, with runtime capability checks and Objective-C exception handling.
- [`SystemShortcuts.swift`](Sources/Flick/SystemShortcuts.swift): reads macOS shortcut settings for conflict detection. [`FlickError.swift`](Sources/Flick/FlickError.swift) supplies errors shown to the user.
- [`Sources/FlickCore/`](Sources/FlickCore/): also contains shortcut models, repeat tracking, and the bounded direction queue. Shared with the unit tests; still macOS-specific.
- [`Tests/FlickCoreTests/`](Tests/FlickCoreTests/): tests that do not move real windows.
- [`Resources/Info.plist`](Resources/Info.plist) and [`scripts/`](scripts/): app bundle metadata, local packaging, and test commands.

## Contributing

Issues and small, focused pull requests are welcome. For move failures, include your macOS version, affected app, display/Space setup, shortcut preset, and Flick's **Last result…** message. Run the development checks above before submitting code; changes to moving windows also need the manual validation steps.

## License

[MIT](LICENSE) © 2026 Gad Kadosh.

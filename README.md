# Flick

A small macOS menu-bar app that moves the focused window to an adjacent desktop Space and follows it.

- **⌥⇧[**: previous Space
- **⌥⇧]**: next Space
- Rapid presses queue moves for the same window, with up to eight waiting steps
- Alternative shortcut presets and optional launch at login
- Uses your configured Mission Control switching shortcuts
- No external dependencies, private APIs, screen capture, SIP changes, telemetry, or network access

**Experimental:** Flick simulates a title-bar drag while switching Spaces. It cannot prove exact window Space membership through public APIs. It is intended for ordinary desktop windows; see the limitations below.

## Build and install

Requires macOS 13+ and Swift 6 / Xcode 16+.

Flick is currently distributed as source. Clone or download this repository, then run these commands from its directory:

```sh
./scripts/build-app.sh
open build/Flick.app
```

The script produces an ad-hoc-signed local app, not a notarized distribution build. It prefers `/Applications/Xcode.app` when available without changing `xcode-select`; you can override `DEVELOPER_DIR`.

The app is built for your Mac's architecture; the script does not produce a universal binary.

To install, quit Flick and copy it to `/Applications` (or `~/Applications`) **before** granting permission or enabling launch at login. Launch the installed copy, not both copies.

1. In Flick's menu, choose **Grant Accessibility…** and enable Flick under **System Settings → Privacy & Security → Accessibility**. If needed, use `+` to add the app.
2. Enable both **Move left a space** and **Move right a space** under **Keyboard → Keyboard Shortcuts → Mission Control**. Flick reads these settings but does not change them.
3. Focus an ordinary window in another app, then press a Flick shortcut. Avoid using the mouse or switching apps during the move.

Keep the app in a stable location. Rebuilding an ad-hoc-signed app may require removing and re-adding its Accessibility entry. For stable signing across rebuilds, set `FLICK_SIGN_IDENTITY` to an installed signing identity.

### Shortcut conflicts

macOS may also reserve Flick's default shortcuts, including implicit Shift variants of Mission Control shortcuts. Successful registration does not guarantee macOS will route the keys to Flick. The menu warns about known overlaps.

If the default does not fire, choose **⌃⌥[ / ⌃⌥]** or **⌃⌥⇧[ / ⌃⌥⇧]** under **Move shortcuts**. A preset identical to an actual Space-switching shortcut is rejected.

Bracket shortcuts use physical US-layout bracket key positions. Arbitrary shortcut recording and layout-aware key selection are not supported. Repeated key-down events are ignored until the bracket key is released; modifiers can stay held between presses.

## Behavior and limitations

Flick finds the focused window through Accessibility, locates a safe title-bar drag point, holds the window, and sends your configured Mission Control shortcut. It waits for a Space-change notification and animation before continuing. Queued steps keep the same window held rather than looking up a new focused window.

After releasing the window, Flick restores the cursor and the small drag displacement. A best-effort visibility check supplies feedback under **Last result…** and in the menu-bar tooltip:

- **Window visible after drop:** the captured window appears in the on-screen window list. This is not proof of exact Space membership.
- **Window not visible after drop:** a warning that the move could not be verified.
- **Window move not verified:** the window could not be identified unambiguously.

The visibility check never triggers further desktop navigation. Flick does not automatically navigate back, even when a move fails or cannot be verified. Navigation failures beep and discard queued steps.

Requests are accepted only while the original window is held, not during drop or verification. A missing Space-change notification stops the sequence; at a desktop boundary Flick does not wrap or create a Space.

Fullscreen/Split View windows and dialogs are rejected. Borderless/custom-title-bar windows may be rejected if no safe drag point is found. Fullscreen destinations, Stage Manager, multiple displays, pinned/all-desktop windows, and unusual animation settings are not supported/validated.

Mouse-up cleanup runs on errors and cancellation, and quitting waits for cleanup. Physical input is not blocked. Force-quitting or crashing the process cannot guarantee cleanup.

### Manual validation

Start with a disposable, non-fullscreen TextEdit window, one display, Stage Manager off, and at least two adjacent ordinary desktop Spaces.

1. Move right and back left. Check that **both the Space and the window** moved.
2. Repeat while keeping the shortcut modifiers held.
3. With three adjacent Spaces, tap right twice quickly. Confirm the same window travels two Spaces. Also test queued opposite directions.
4. Test the desktop boundary: remaining queued steps should be discarded without navigating back.
5. Test a fullscreen window (should reject), your usual apps, and quitting during a move (should release the mouse).

A successful build or a detected Space change does not replace these checks.

## Development

```sh
./scripts/test.sh
./scripts/build-app.sh
build/Flick.app/Contents/MacOS/Flick --diagnose
build/Flick.app/Contents/MacOS/Flick --smoke-test
```

The unit tests cover shortcut parsing and conflicts, preset modifier conversion, synthetic event construction, hotkey repeat handling, animation-delay accounting, and queue ordering/capacity/closure. They do not execute the window-moving operation or prove its cleanup behavior.

`--diagnose` reads settings/permission status and briefly registers/unregisters hotkeys without posting input. `--smoke-test` briefly starts the menu-bar app with move callbacks disabled and exits. Quit any running Flick instance before either check so its registrations do not interfere. Accessibility permission reported from a terminal-run binary may differ from the app launched through Finder/LaunchServices.

### Code map

The main path is **hotkey → app delegate → window mover → synthetic input**.

- [`FlickMain.swift`](Sources/Flick/FlickMain.swift): starts the app or runs diagnostics.
- [`AppDelegate.swift`](Sources/Flick/AppDelegate.swift): owns the menu, preferences, hotkeys, and asynchronous move task.
- [`HotKeys.swift`](Sources/Flick/HotKeys.swift): registers global shortcuts and reports distinct presses.
- [`WindowMover.swift`](Sources/Flick/WindowMover.swift): captures a window, performs the gesture, and cleans up.
- [`SystemShortcuts.swift`](Sources/Flick/SystemShortcuts.swift): reads macOS shortcut settings. [`FlickError.swift`](Sources/Flick/FlickError.swift) supplies errors shown to the user.
- [`Sources/FlickCore/`](Sources/FlickCore/): shortcut models, input-event construction, timing, repeat tracking, and the bounded move queue. Shared with the unit tests; still macOS-specific.
- [`Tests/FlickCoreTests/`](Tests/FlickCoreTests/): tests that do not post input or move windows.
- [`Resources/Info.plist`](Resources/Info.plist) and [`scripts/`](scripts/): app bundle metadata, local packaging, and test commands.

## Contributing

Issues and small, focused pull requests are welcome. For move failures, include your macOS version, affected app, display/Space setup, shortcut preset, and Flick's **Last result…** message. Run the development checks above before submitting code; changes to moving windows also need the manual validation steps.

## License

[MIT](LICENSE) © 2026 Gad Kadosh.

# Flick

A small, local macOS menu-bar prototype for moving the focused window to an adjacent desktop Space.

- **⌥⇧[**: previous Space
- **⌥⇧]**: next Space
- **Follow moved window**: configurable and saved; on by default
- Rapid presses queued for the same held window (up to eight waiting steps)
- Alternative shortcut presets and optional launch at login
- Reads your actual Mission Control switching shortcuts, including your **⌥[ / ⌥]** settings
- No external dependencies, private APIs, screen capture, or SIP changes

## Build and run

```sh
./scripts/build-app.sh
open build/Flick.app
```

Swift 6 / Xcode 16+ is required. The scripts prefer `/Applications/Xcode.app` when available, without changing `xcode-select`. You can override `DEVELOPER_DIR`. The build script produces an ad-hoc-signed local app at `build/Flick.app`; this is not a notarized distribution build.

In Flick's menu, choose **Grant Accessibility…**, and enable **Flick** under **System Settings → Privacy & Security → Accessibility**. If needed, use the `+` button to add `build/Flick.app`. Keep the app in a stable location. Rebuilding an ad-hoc-signed app may require removing and re-adding its Accessibility entry. For stable signing across rebuilds, set `FLICK_SIGN_IDENTITY` to an installed signing identity.

To install, quit Flick and copy it to `/Applications` (or `~/Applications`) **before** granting permission or enabling launch at login. Launch the installed copy, not both copies.

Both **Move left a space** and **Move right a space** should be enabled in **Keyboard → Keyboard Shortcuts → Mission Control**. Flick does not edit those settings.

### Shortcut overlap

macOS also reserves implicit Shift variants of the Space-switching shortcuts. On this machine, symbolic shortcut IDs **80/82** overlap **⌥⇧[ / ⌥⇧]**. Carbon registration succeeds, but that does not prove macOS will route the keystrokes to Flick. The menu warns about overlaps. If the default does not fire, try **⌃⌥[ / ⌃⌥]** or **⌃⌥⇧[ / ⌃⌥⇧]** under **Move shortcuts**. A preset identical to the actual left/right switching shortcuts is rejected.

Bracket shortcuts use physical US-layout bracket key positions; arbitrary shortcut recording and layout-aware key selection are not implemented yet.

## How the prototype works

1. Find the frontmost app's focused, ordinary window through Accessibility.
2. Locate a visible title-bar drag point; hit-test to avoid tabs and controls.
3. Check that no mouse button is held (modifier keys may stay held), press and drag the title bar slightly, and synthesize your configured Space-switching shortcut with its own exact modifier flags. The pre-switch event delays total 40 ms, down from 250 ms.
4. Wait for a Space-change notification and animation. If another press was queued, switch again while holding the **same window**, without another window lookup/drop/drag setup. Otherwise release the mouse. Time spent waiting for each notification counts toward that switch's 650 ms settling budget.
5. Best-effort check that the same window is visible after the drop, using public WindowServer metadata. This does **not** establish exact Space membership, especially with multiple displays.
6. If **Follow moved window** is off, retrace all confirmed switches in reverse order to return to the starting Space after the burst. Restore the cursor and the window's small drag displacement.

Rapid presses are accepted only while the captured window is held. During the brief drop/verification or stay-here return trip, further presses are rejected, rather than replayed against a different window. A failed switch/boundary cancels all remaining queued requests; stay-here mode attempts to retrace the confirmed portion of the route. Cancellation/quit releases the mouse and discards the queue. Animations are still serialized; queueing removes the need to time key presses, not the native animation itself.

Mouse-up cleanup runs on errors and cancellation. Quit during a move waits for cleanup. Physical input is not blocked: avoid moving the mouse or switching apps during the gesture. Force-quitting/crashing the process cannot guarantee cleanup.

**This backend is experimental.** A successful build or a detected Space change does not prove the window was moved. If window identity cannot be matched unambiguously, the last result explicitly says the move was not verified. The single-step version, including held modifiers and shorter delays, was reported working on the user's macOS 27 desktop. The queued multi-step drag still needs manual validation; unit tests do not replace that.

Fullscreen/Split View windows and dialogs are rejected. Borderless/custom-title-bar windows can be rejected if no safe drag point is found. Fullscreen destinations, Stage Manager, multiple displays, pinned/all-desktop windows, and unusual animation settings are not supported/validated. At a desktop boundary, a missing Space-change notification produces an error rather than wrapping or creating a Space. **Stay here** necessarily has a visible out-and-back transition with this backend.

Failures beep and are available under **Last result…** and in the menu-bar icon's tooltip. The result also reports milliseconds from move preparation to requesting the Space switch, to help distinguish Accessibility lookup delays from the native animation. Repeated hotkey-pressed events are ignored until that bracket key is released; you can keep the modifiers held between presses. No background telemetry or network access.

## First manual test

Use a disposable, non-fullscreen **TextEdit** window and at least two adjacent ordinary desktop Spaces, initially on one display with Stage Manager off.

1. Enable Accessibility and focus TextEdit (not Flick's settings alert).
2. Keep **Follow moved window** on. Press **⌥⇧]**; try both releasing all keys and keeping Option/Shift held. Do not use the mouse during the move.
3. Check that **both the Space and the window** moved. If nothing happens, try the alternative preset. If it beeps, inspect **Last result…**.
4. Move back with **⌥⇧[** (or the selected preset).
5. Turn **Follow moved window** off, refocus TextEdit, and repeat. Confirm the window moved but you returned to your starting Space.
6. With **three adjacent ordinary Spaces**, turn follow on, refocus TextEdit, and tap **⌥⇧] twice quickly**, keeping the modifiers held. Confirm the same window travels two Spaces. Also test queued opposite directions, then a burst with follow off (should return to the starting Space).
7. Test the desktop boundary, a fullscreen window (should reject), and your usual apps. A burst that reaches a boundary must discard remaining steps, not move another window.

If the title-bar/switch technique fails on your OS, the next step is to replace this isolated `WindowMover` backend with a Mission Control drag implementation or a separately opt-in private-API backend—not to weaken system security.

## Validation and diagnostics

```sh
./scripts/test.sh
./scripts/build-app.sh
build/Flick.app/Contents/MacOS/Flick --diagnose
build/Flick.app/Contents/MacOS/Flick --smoke-test
```

The unit tests cover shortcut parsing, disabled/malformed settings, presets, implicit system conflicts, synthetic event flags/source configuration (without posting input), hotkey repeat handling, animation-delay accounting, FIFO burst ordering, bounded queue capacity, queue cancellation, and partial-route return planning. `--diagnose` reads settings/permission status and briefly registers/unregisters hotkeys; it does not post input or move windows. `--smoke-test` briefly starts the menu-bar app with move callbacks disabled and exits. Permission reported from a terminal-run binary may differ from the app launched through Finder/LaunchServices. Quit any running Flick instance before these checks so its registrations do not interfere.

Sources: `Sources/Flick/` (app and automation), `Sources/FlickCore/` (shortcut models), `Tests/FlickCoreTests/` (unit tests), `Resources/Info.plist` (bundle metadata).

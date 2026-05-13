## Why

The `app-shell` capability previously required that real process termination be reachable **only** via the menu bar status item's right-click context menu. In practice that left the main window with no real-quit affordance at all — ⌘Q and the application-menu Quit item are intercepted into "close all windows", so users with the main window in focus had no way to fully exit without hunting for the status item.

A real-quit button was added to the main window's sidebar footer in PR #7 (already merged). This change is a docs-only catchup so the `app-shell` spec stops contradicting the shipped code.

## What Changes

- Relax the `app-shell` Quit-semantics requirement: drop the **only** clause, document the main-window sidebar footer as a second `userInitiatedQuit` path alongside the status item.
- Add a scenario covering the new sidebar-footer path.

No code changes. The implementation already shipped in `9b439f7` ("feat(main-window): add real-quit button to sidebar footer").

## Capabilities

### Modified Capabilities
- `app-shell`: real process termination is now reachable from either the menu bar status item right-click menu OR the main window sidebar footer; both paths set `userInitiatedQuit` before invoking `NSApp.terminate(_:)`.

## Impact

- **Spec**: one requirement reworded in `app-shell` + one new scenario.
- **Code**: none (already merged).
- **Behavior**: unchanged from current `main`. The intercept of ⌘Q / app menu Quit is preserved; only the set of *user-initiated* exit paths grows.
- **Out of scope**: changing the ⌘Q intercept, adding a confirmation dialog, exposing real-quit from the dashboard toolbar or any other surface.

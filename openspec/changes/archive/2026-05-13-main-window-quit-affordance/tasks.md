## 1. Implementation

- [x] 1.1 Add `quitButton` to `MainWindowContent.sidebarFooter`, calling `AppDelegate.requestRealQuit()` (shipped in PR #7, commit `9b439f7`)
- [x] 1.2 Hide the button when the sidebar is collapsed
- [x] 1.3 Tooltip: "Quit TokenTrace (stops background sync)"; hover state turns the icon red

## 2. Spec sync

- [x] 2.1 Reword the `app-shell` Quit-semantics requirement to remove the **only** clause and document the sidebar-footer path
- [x] 2.2 Add a "Real Quit from the main window sidebar" scenario
- [x] 2.3 `openspec validate main-window-quit-affordance --strict` passes

## 3. Archive

- [x] 3.1 After merge, run `openspec archive main-window-quit-affordance` to fold deltas into `openspec/specs/app-shell/spec.md`

Add OverlayPortalController
**Is your feature request related to a problem? Please describe.**

There's a [OverlayPortalController](https://api.flutter.dev/flutter/widgets/OverlayPortalController-class.html) class. I'd like to have a hook like `useOverlayPortalController()`

### Additional contract requirements

- `useOverlayPortalController()` returns an `OverlayPortalController` that is created once and preserved across rebuilds of the widget that uses the hook.
- The returned controller exposes `isShowing`, `show()`, and `hide()` to control overlay visibility.
- In offstage diagnostics, a `HookBuilder` using this hook includes the exact entry ` │ useOverlayPortalController: OverlayPortalController DETACHED`.

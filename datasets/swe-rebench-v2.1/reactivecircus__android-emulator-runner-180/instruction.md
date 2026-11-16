Support non-mobile targets (Wear OS, TV)
Currently the list of allowed targets are:
- `default`
- `google_apis`
- `google_apis_playstore`

However, `sdkmanager` and `avdmanager` also have images to support emulators for other devices:
- `android-wear`
- `android-wear-cn`
- `android-tv`
- `google-tv`

Since the specified target is validated, right now there's no easy way to use any of those 4 targets.

A few possible solutions:
- Expand the allowed list to include all 7 currently available targets
- Remove the strict validation for the targets, to guard against new ones
- Some combination of both (check if it is a recognized target, and if not, warn but don't fail)

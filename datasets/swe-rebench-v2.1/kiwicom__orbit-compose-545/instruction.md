Alert usage lint - put buttons to actions slot.
It would be useful to lint that buttons are put into action slot and not in content.

### Additional contract requirements

- Provide a lint issue `DialogButtonsInContentSlotDetector.ISSUE` in the companion object of `DialogButtonsInContentSlotDetector`. The issue id is `DialogButtonsInContentSlotDetector` and its severity is `Severity.ERROR`.
- When a `ButtonPrimary` is placed in the content slot of an Orbit alert dialog, report the message `ButtonPrimary in Dialog's content slot. Use actions slot for CTAs instead.`
- When a `ButtonCritical` is placed in the content slot of an Orbit alert dialog, report the message `ButtonCritical in Dialog's content slot. Use actions slot for CTAs instead.`

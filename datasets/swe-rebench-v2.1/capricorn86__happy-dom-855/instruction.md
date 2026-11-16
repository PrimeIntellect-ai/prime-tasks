Missing window.SubmitEvent
**Is your feature request related to a problem? Please describe.**
Presently, there is no `window.SubmitEvent` available.

**Describe the solution you'd like**
Add one, as has been done for other common event types. Seems like the only attribute you'd need to add is a `SubmitEvent.submitter` property as per [these docs](https://developer.mozilla.org/en-US/docs/Web/API/SubmitEvent).

**Describe alternatives you've considered**
The alternative is to construct a base `Event` and add a `submitter` to it manually.

### Additional contract requirements

- Provide `SubmitEvent` as an `Event` subclass available on `window`. Its constructor accepts the event type and the standard event options, including `bubbles`, `cancelable`, and `submitter`. Its `submitter` property is the supplied element, or `null` when no submitter is supplied.
- `HTMLFormElement.requestSubmit()` dispatches a `submit` event that is a `SubmitEvent` when the form is valid or validation is bypassed with `noValidate`. The event's submitter is the supplied submit button, or the form itself when no submitter is supplied.

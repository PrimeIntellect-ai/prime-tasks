Persisting errors when off-screen for validation components
**Is your feature request related to a problem? Please describe.**
Currently errors disappear when the component that is being validated is no longer rendered. For example, a paginated table with some validated text inputs. If I make a validation error on page 2 and switch to page 3 that error disappears.

**Describe the solution you'd like**
I'm unsure if there are any existing workarounds for this(?) I can't find any, please let me know if there are. It would be nice to have an option to persist errors when the component is not rendered, until they are fixed.

Even if this means the component needs a unique identifier to be provided. [HIDDEN]

**Describe alternatives you've considered**
I've considered trying to do this manually by pulling the errors out into a separate variable whenever a page change occurs, but this likely only works for that specific use-case.

### Additional contract requirements

- The `ValidationProvider` component accepts a boolean `persist` prop (default `false`). When `persist` is `true`, the provider has a `vid`, and it is nested inside a `ValidationObserver`, its validation errors are retained while the provider is not rendered and are shown again once it is rendered again.
- Persisted errors must stop appearing once the value is corrected and validation succeeds; the result of the next validation replaces any persisted errors for that provider.

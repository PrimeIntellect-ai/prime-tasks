Update inputProvider to toggle on serviceName not language
**Is your feature request related to a problem? Please describe.**
Now that the font applied to a component will be based on the service #573 , we currently have to include `LANGUAGE_VARIANTS` to make a select knob in storybook. This means we will have two select input knobs with the same values and the user will have to select twice.

**Describe the solution you'd like**
Update `inputProvider` to have a dropdown of services, not languages, and then return the service name out in the provider for the components to use.

**Testing notes**
[Tester to complete]

Dev insight: Unit Tests will be sufficient

**Additional context**
Add any other context or screenshots about the feature request here.


Blocking https://github.com/bbc/psammead/issues/543

### Additional contract requirements

- `inputProvider(slots, componentFunction)` and `dirDecorator(storyFn)` are exported from the `@bbc/psammead-storybook-helpers` package.
- The render callback passed to `inputProvider` receives a single object with `slotTexts` (an array of strings, one per slot), `script`, `dir` and `service` (the selected service name).
- `dirDecorator` passes `script`, `dir` and the selected `service` name to the wrapped story.
- The service selector offers the available service names, including `news`, `russian` and `arabic`, and does not offer language names such as `english`.

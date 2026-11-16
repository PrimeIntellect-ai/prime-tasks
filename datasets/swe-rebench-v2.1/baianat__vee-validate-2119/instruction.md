[Feature request] Renderless components
**Is your feature request related to a problem? Please describe.**
Deep styling components wrapped with `ValidationObserver` or `ValidationProvider` is more complex as a result of a wrapping element being present in the DOM. I am able to work around this for now but the solution I currently utilize is not ideal.

**Describe the solution you'd like**
Support a property that allows these components to be rendered without the wrapping DOM element.

**Describe alternatives you've considered**
Simply waiting for Vue 3 to natively support fragments should make the wrapping element unnecessary and this property not necessary either.

**Additional context**
[portal-vue](https://linusborg.github.io/portal-vue/#/guide?id=removing-the-wrapper-element) allows a `slim` property to be specified for its `portal-target` component to remove the wrapping element. Can the same thing be done here? In my use case, I know I will always have one root node so this should work.

### Additional contract requirements

`ValidationProvider` and `ValidationObserver` must each accept a boolean `slim` property. When `slim` is enabled, the component must render its slot content without adding the usual wrapping DOM element.

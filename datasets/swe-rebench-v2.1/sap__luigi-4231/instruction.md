add 'setCurrentLocale' to wc client uxManager
... and dispatch corresponding event in container and compoundContainer

### Additional contract requirements

- The web component client API's `uxManager` exposes a method `setCurrentLocale(locale: string)` that returns no value (void).
- Calling it dispatches the `SET_CURRENT_LOCALE_REQUEST` event with payload `{ currentLocale: locale }`.
- If `locale` is falsy (for example an empty string), no event is dispatched and no error is raised.
- The locale request is supported in both standard-container and compound-container contexts.

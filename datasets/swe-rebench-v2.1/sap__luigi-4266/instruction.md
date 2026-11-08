Make it possible to preserve non-client viewgroup iframes
by adding an option for a viewGroup in viewGroupSettings, e.g. **noClientCheck** or sth., that prevents a nav check when reactivating the iframe, which currently leads to a reload because there is no **luigi.navigation.ok** response.

### Additional contract requirements

- The view group setting that disables the client check is named `noClientCheck` and is a boolean.
- The handshake-failure check is available as a public method `initHandshakeFailed(config)` on the `Iframe` service (`core/src/services/iframe.js`). It returns `true` when the handshake with Luigi has failed (for example when the Luigi handshake object is missing or `initOk` is not set) and `false` otherwise. When the view group of the iframe (`config.iframe.vg`) has `noClientCheck` set to `true`, it returns `false`.
- View group settings are read through the public helper `NavigationHelpers.getViewGroupSettings(viewGroup)`, which returns the settings object for the given view group.

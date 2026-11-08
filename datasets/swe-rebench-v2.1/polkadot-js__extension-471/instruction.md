Add ErrorBoundary (as applicable)
Wile https://github.com/polkadot-js/extension/issues/468 (based on description) seems like a background crash (???), the UI itself should never go "white page" or drop out. ErrorBoundary (as used in the apps UI) protects against that.

Need at least one for the authorization/signing where things may go wrong due to bad parsing.

### Additional contract requirements

- If a screen of the extension popup fails while rendering, the popup must keep showing content (for example an error message with a way back to the home screen) instead of going blank or dropping out of the UI.
- At least one authorization or signing screen must be protected the same way: when an incoming authorization request cannot be rendered (for example because its details are missing or malformed), the popup still shows content rather than a blank page.

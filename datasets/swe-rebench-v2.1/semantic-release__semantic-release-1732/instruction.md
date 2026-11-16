Cannot disable CI checks in shareable configurations
## Current behavior

`ci: false` defined in the _shareable_ configuration is not respected.

This is because [HIDDEN] and the rest of the code checks only `options.noCi` (at least in the places I checked).

Workaround: add `noCi: true` in the shareable configuration.

## Expected behavior

- Should be OK to set `ci: false` in the shareable configuration - happy to PR this.
- Alternatively, [documentation should be updated](https://semantic-release.gitbook.io/semantic-release/usage/configuration#ci) to reflect that - happy, but not _too_ happy, to PR this as well.

## Environment

- **semantic-release** version: latest

### Additional contract requirements

- A `ci: false` setting in a shareable configuration must be respected. When `ci` is `false`, whether set directly or through a shareable configuration, the options resolved by `getConfig` must keep `ci` as `false` and set `noCi` to `true`.

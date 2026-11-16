Invalid version of github.com/drone/drone-template-lib
You changed the version of `github.com/drone/drone-template-lib` from v1.0.0 in this [commit](https://github.com/appleboy/drone-telegram/commit/47352c6cca24f624b46e5093a77f41a1ba499bd5#diff-33ef32bf6c23acb95f5902d7097b7a1d5128ca061167ec0716715b0b9eeaa5f6L6) to v1.0.1-x to fix the issue in #89 and #92. Also see [#47](https://github.com/drone-plugins/drone-webhook/issues/47)

With your latest release / version v1.3.9 you accidentally changed the version of `github.com/drone/drone-template-lib` back to v1.0.0 which breaks the templating functions `duration`, `datetime` and `since` because these functions expect a `float64` value but _build.started_ and _build.finished_ are `int64` values.

I guess there are two possible solutions: [HIDDEN] or opening a PR on the [drone-template-lib](https://github.com/drone/drone-template-lib) project to release a new version with the correct values; the master branch already has the correct `int64` type, but the released branch v1.0.0 uses the old `float64` type.

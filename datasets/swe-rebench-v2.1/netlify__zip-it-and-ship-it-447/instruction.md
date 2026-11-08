Add support for source maps
**- Do you want to request a _feature_ or report a _bug_?**

Feature.

**- What is the expected behavior?**

When using functions created by `zip-it-and-ship-it` for local development, it would be useful to have access to source maps to ease debugging.

We could add a `sourcemap` configuration property, which could potentially be enabled by default when `archiveType` is `none`.

This would improve the experience of serving bundled functions in the CLI (https://github.com/netlify/cli/pull/2094).

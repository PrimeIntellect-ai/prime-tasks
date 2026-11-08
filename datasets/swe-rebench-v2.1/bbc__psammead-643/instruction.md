Psammead timestamp container - Accept and use moment locale
**Is your feature request related to a problem? Please describe.**
We need to use different moment locales for different services

**Describe the solution you'd like**
Accept a 'locale' prop, and tell moment to use it. This makes the assumption that the locale is available to the package.

[HIDDEN]

**Testing notes**
[Tester to complete]

Dev insight: Unit tests, storybook examples

**Additional context**
Add any other context or screenshots about the feature request here.

### Additional contract requirements

- When a `locale` prop is supplied, use that locale for timestamp formatting, assuming the locale is available to the package.

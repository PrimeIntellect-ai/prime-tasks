Release 1.6.0 editor crashes when dependencies are used
### Prerequisites

- [x] I have read the [documentation](https://react-jsonschema-form.readthedocs.io/);
- [x] In the case of a bug report, I understand that providing a [SSCCE](http://sscce.org/) example is tremendously useful to the maintainers.
- [x] Ideally, I'm providing a [sample JSFiddle](https://jsfiddle.net/n1k0/f2y3fq7L/6/) or a [shared playground link](https://mozilla-services.github.io/react-jsonschema-form/) demonstrating the issue.

### Description

With the latest release 1.6.0 we now see an issue for all fields where we use dependencies. The issue causes the editor to not render at all. In our own build we see the console.log stating that the dependency-based fields are not defined.

Everything works in 1.5.0 - but we're eager to shift to 1.6.0 to enable default values in anyOf dependencies, as listed in issue #1293

### Steps to Reproduce
For us, all fields that have dependencies now cause the editor to break - incl. the playground sample shared above (you can verify this by copying the Schema into a new playground and observe that it does not render):
[example (worked in 1.5.0, but not 1.6.0)
](https://mozilla-services.github.io/react-jsonschema-form/#eyJmb3JtRGF0YSI6eyJydGMiOnsic3luYyI6MH19LCJzY2hlbWEiOnsidHlwZSI6Im9iamVjdCIsInByb3BlcnRpZXMiOnsicnRjIjp7InRpdGxlIjoiQ29uZmlndXJlIENsb2NrIiwidHlwZSI6Im9iamVjdCIsInByb3BlcnRpZXMiOnsic3luYyI6eyJ0aXRsZSI6IlRpbWUgU3luYyBUeXBlIiwidHlwZSI6ImludGVnZXIiLCJkZWZhdWx0IjowLCJhbnlPZiI6W3sidGl0bGUiOiJSZXRhaW4gdGltZSIsInR5cGUiOiJpbnRlZ2VyIiwiZW51bSI6WzBdfSx7InRpdGxlIjoiQXV0byB0aW1lIiwidHlwZSI6ImludGVnZXIiLCJlbnVtIjpbMV19XX19LCJkZXBlbmRlbmNpZXMiOnsic3luYyI6eyJvbmVPZiI6W3sicHJvcGVydGllcyI6eyJzeW5jIjp7ImVudW0iOlswXX19fSx7InByb3BlcnRpZXMiOnsic3luYyI6eyJlbnVtIjpbMV19LCJ0b2xlcmFuY2UiOnsidGl0bGUiOiJUaW1lIHN5bmMgdG9sZXJhbmNlIiwidHlwZSI6ImludGVnZXIiLCJtaW5pbXVtIjoxLCJtYXhpbXVtIjozNjAwLCJkZWZhdWx0IjozMH19fV19fX19fSwidWlTY2hlbWEiOnt9fQ==)

In contrast, the same example will still render if I completely remove the "dependencies" tab - but of course that's probably not the intention. I assume some issue has arisen during the implementation of a fix for default values.
[same example after removing dependencies (works in 1.5.0 and 1.6.0)](https://mozilla-services.github.io/react-jsonschema-form/#eyJmb3JtRGF0YSI6eyJydGMiOnsic3luYyI6MH19LCJzY2hlbWEiOnsidHlwZSI6Im9iamVjdCIsInByb3BlcnRpZXMiOnsicnRjIjp7InRpdGxlIjoiQ29uZmlndXJlIENsb2NrIiwidHlwZSI6Im9iamVjdCIsInByb3BlcnRpZXMiOnsic3luYyI6eyJ0aXRsZSI6IlRpbWUgU3luYyBUeXBlIiwidHlwZSI6ImludGVnZXIiLCJkZWZhdWx0IjowLCJhbnlPZiI6W3sidGl0bGUiOiJSZXRhaW4gdGltZSIsInR5cGUiOiJpbnRlZ2VyIiwiZW51bSI6WzBdfSx7InRpdGxlIjoiQXV0byB0aW1lIiwidHlwZSI6ImludGVnZXIiLCJlbnVtIjpbMV19XX19fX19LCJ1aVNjaGVtYSI6e319)

Martin

### Additional contract requirements

When no form data is supplied, defaults declared within nested dependency schemas must be included in the resulting form data.

- For a schema with a nested dependency, `getDefaultFormState(schema, { can_1: { phy: null } })` must preserve the explicit null and return `{ can_1: { phy: null } }`.

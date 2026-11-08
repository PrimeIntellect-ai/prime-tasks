Any API-specific override resets all root settings
**Describe the bug**

Defining any API-specific override results in all non-customized props not receiving the root values.

**To Reproduce**
Steps to reproduce the behavior:
1. Given this `redocly.yaml` file
    ```yaml
        apis:
          repro@bug:
            root: openapi.yaml
            decorators: {}
        extends:
          - recommended
    ```
2. And this OpenAPI file (without any Info license which will cause a warning with the `recommended` rules):
    ```yaml
    openapi: 3.1.0
    info:
      version: 1.0.0
      title: Example.com
      termsOfService: 'https://example.com/terms/'
      description: Sample.
    servers:
      - url: 'https://{tenant}/api/v1'
        variables:
          tenant:
            default: www
            description: Your tenant id
      - url: 'https://example.com/api/v1'
    paths: {}
    ```
3. Run this command with these arguments... `redocly lint`
4. See error (`Woohoo! Your OpenAPI definition is valid. 🎉` with no mention of any warning)

**Expected behavior**

I expected the above repro to say there is 1 warning.

I expect that `extends` defined at the root level of the configuration will apply to every API unless that API specifically overrides the `extends` property itself (even if it overrides a decorator as shown above).

For example, a specific override:

```yaml
        apis:
          repro@bug:
            root: openapi.yaml
            decorators: {}
            extends: []
        extends:
          - recommended
```

**Logs**
<!-- If applicable, add logs to help explain your problem. -->
n/a

**Redocly Version(s)**
<!-- What version of Redocly CLI are you using? -->
- 1.0.0-beta.110
- 1.0.0-beta.109

It works in 1.0.0-beta.108 (although I needed to adjust the Redocly configuration file to reflect changes):
```yaml
apis:
  repro@bug:
    root: openapi.yaml
    styleguide:
      decorators: {}
styleguide:
  extends:
    - recommended
```

**`Node.js` Version(s)**
16

**Additional context**

- Discovered when trying to reproduce #898

### Additional contract requirements

API-specific styleguide settings must not discard root-level settings that the API does not override. A root-level `extends` applies to each API unless that API specifies its own `extends`; an explicitly empty API `extends` list disables root extensions for that API.

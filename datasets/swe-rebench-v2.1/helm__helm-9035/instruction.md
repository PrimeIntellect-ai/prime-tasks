Helm function 'fail' should not fail when doing 'helm lint'
When executing `helm lint` directives such as this fail the linting:

```yaml
failure: {{ fail "this is a failure!" }}
```

The same problem was already fixed for the `required` function: https://github.com/helm/helm/pull/4221
An issue had already been written on `failure` but was closed due to inactivity: https://github.com/helm/helm/issues/3026

In order to lint charts using `fail` this needs to be fixed.

Reference: https://helm.sh/docs/chart_template_guide/function_list/#fail

### Additional contract requirements

- During linting, a `fail` invocation must not abort the lint operation and must contribute an empty string to rendered output.
- Outside linting, a `fail` invocation must continue to terminate rendering with an error.

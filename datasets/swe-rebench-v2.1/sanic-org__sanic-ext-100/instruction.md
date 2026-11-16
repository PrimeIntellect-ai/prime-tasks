[Feature Request] If `API_SCHEMES` is defined in config and is not a list, try to convert it into one
**Is your feature request related to a problem? Please describe your use case.**
Currently the config value for `API_SCHEMES` is interpreted as-is but is used as an iterable, which makes it hard to use when it is defined using environment variables, as these are always strings.
https://github.com/sanic-org/sanic-ext/blob/993d9d7e92efe90909af90d521a664bf742c8035/sanic_ext/extensions/openapi/blueprint.py#L161

**Describe the solution you'd like**
It would be nice if, in cases in which it is a string, it would split the string automatically (maybe in `,`) to convert it into a list.

**Additional context**
N/A.

### Additional contract requirements

- If `API_SCHEMES` is explicitly set to `None`, use the default `http` scheme when generating server URLs; with `API_HOST` set to `example.com`, the URL is `http://example.com/`.

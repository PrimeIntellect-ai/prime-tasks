Custom HTTP header without a space
 - H <HEADERS>                       Custom HTTP header. Examples: -H "foo: bar"
 - If I use it like -H "foo:bar" -> Error: Parse header
 - The problem is that gitlab ci schema do not allowed

```yaml
oha test:
  image:
    name: apoutchika/oha
  stage: stress_test
  script:
    - oha -V
    - oha -H "API-KEY: ${API_KEY}" https://xxx
```

- oha -H "API-KEY: ${API_KEY}" https://xxx  -> jobs:oha test sfinga:script config should be a string or a nested array of strings up to 10 levels deep

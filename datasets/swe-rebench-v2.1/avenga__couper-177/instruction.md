`req.json_body` result is an empty object for specific types
**Describe the bug**
The variable `req.json_body` does not return the expected outcome.

**To Reproduce**
Steps to reproduce the behavior:
1. Which Couper version? Run `couper version` or `docker run --entrypoint=/couper avenga/couper version`
`master 2021-03-29 acfce46`
2. Provide your configuration file `*.hcl`. Remove sensitive data.
```hcl
server "api" {
  api {
    base_path = "/api"

    endpoint "/req" {
      response {
#        body = json_encode(req.json_body)
        body = json_encode([1,2,3])
      }
    }
  }
}
```


3. Provide a `curl` call for reproduction
`curl -s -H "Content-Type: application/json" -d "[1,2,3]" localhost:8080/api/req|jq`

**Expected behavior**
- `json_encode([1,2,3])`: got expected

```json
 [
  1,
  2,
  3
]
```

- `json_encode(req.json_body)` got empty object, expected array with `1, 2, 3`

```json
 {}
```

**Additional context**
This happens with `boolean`, `number`, `string` or `array` values.

`operation-2xx-response` validation does not respect '2XX' response code
**Describe the bug**
`operation-2xx-response` does not respect '2XX' response code. According to OAI3 '2XX' is a valid range response code definition.
Validation result:
```
OpenAPI 3.x detected

/tmp/build/test.yaml
 13:17  warning  operation-2xx-response  Operation must have at least one `2xx` response.  paths./test.post.responses

✖ 1 problem (0 errors, 1 warning, 0 infos, 0 hints)
```

**To Reproduce**

```
openapi: "3.0.0"
info:
  version: test
  title: test
  description: test

servers:
  - url: /

paths:
  '/test':
    post:
      responses:
        '2XX':
          description: Success!
        default:
          description: default
```

**Expected behavior**
No warnings or errors after validation

**Environment (remove any that are not applicable):**
 - Library version: 5.9.1 (via docker image)

**Additional context**
We use OAI to describe an API that our customers would have to implement in order to integrate with our system. Any 2xx would be accepted as successful response.

### Additional contract requirements

In OpenAPI 2.0, a response key of `2XX` does not satisfy the success-response rule.

Path Params being applied to more than http operations
**Describe the bug**
the `path-params` rule is being applied to more than just http operations defined under a path.

**To Reproduce**

```
openapi: 3.0.1
paths:
  /hello/{id}:
    x-dont-path-param-me: hello
    get:
      tags:
        - metadata
      operationId: list-data-sets
      summary: List available data sets
      responses:
        '200':
          description: Returns a list of data sets
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
```

output:
```
  1:1  warning  info-contact           Info object should contain `contact` object.
  1:1  warning  info-description       OpenAPI object info `description` must be present and non-empty string.
  1:1  warning  oas3-api-servers       OpenAPI `servers` must be present and non-empty array.
  1:1    error  oas3-schema            Object should have required property `info`.
  1:1  warning  openapi-tags           OpenAPI object should have non-empty `tags` array.
 4:27    error  path-params            The operation does not define the parameter `{id}` expected by path `/hello/{id}`.
  5:9  warning  operation-description  Operation `description` must be present and non-empty string.
 7:11  warning  operation-tag-defined  Operation tags should be defined in global tags.
```

you can see here that the path params rule is being applied to `x-dont-path-param-me`

**Expected behavior**
I expect it to only be applied to the standard http operations (get, post, put, delete, options, etc)

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Environment (remove any that are not applicable):**
 - Library version: 5.4.0
 - OS: MacOS 10.15.3

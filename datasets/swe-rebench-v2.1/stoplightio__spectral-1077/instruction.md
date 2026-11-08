Path Parameter Definitions Not Required Across Operations
**Describe the bug**
The `path-params` rule is not triggered when a path parameter is defined under one operation but not in another, both of which are under the same path item.

**To Reproduce**
Given the following OpenAPI document:

```yaml
openapi: 3.0.3
info:
  title: API Title
  version: '1.0'
paths:
  /test/{foo}:
    get:
      parameters:
        - name: foo
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: OK
    put:
      responses:
        '200':
          description: OK
```

I get this when linting:

```
$ spectral lint .\openapi.yaml
OpenAPI 3.x detected

c:/dev/openapi.yaml
  1:1  warning  oas3-api-servers       OpenAPI `servers` must be present and non-empty array.
  1:1  warning  openapi-tags           OpenAPI object should have non-empty `tags` array.
  2:6  warning  info-contact           Info object should contain `contact` object.
  2:6  warning  info-description       OpenAPI object info `description` must be present and non-empty string.
  7:9  warning  operation-description  Operation `description` must be present and non-empty string.
  7:9  warning  operation-operationId  Operation should have an `operationId`.
  7:9  warning  operation-tags         Operation should have non-empty `tags` array.
 17:9  warning  operation-description  Operation `description` must be present and non-empty string.
 17:9  warning  operation-operationId  Operation should have an `operationId`.
 17:9  warning  operation-tags         Operation should have non-empty `tags` array.

✖ 10 problems (0 errors, 10 warnings, 0 infos, 0 hints)
```

**Expected behavior**
This should have triggered the `path-params` rule for the `put`, which is what I get without the parameter definition in the `get`.

```
6:15    error  path-params            The path `/test/{foo}` uses a parameter `{foo}` that does not have a corresponding definition.
```

**Environment:**
 - Library version: 5.3.0
 - OS: Windows 10

### Additional contract requirements

When the `path-params` rule reports a path template parameter that is not defined for an operation, the diagnostic is attributed to the operation that omits the definition:

- message: ``The operation does not define the parameter `{<name>}` expected by path `<path>`.``
- path: `['paths', '<path>', '<operation>']`

This holds both when no operation defines the parameter and when another operation on the same path item defines it.

The diagnostic described above replaces the diagnostic shown in the reproduction's expected output.

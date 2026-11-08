Camel case function does not accommodate uppercase single letter words at the end of a property name
**Describe the bug**

When using the built-in function `casing` with the argument `camel` Spectral raises an error when it encounters a single, uppercase word at the end of the camel-cased string. For example:

* coordinateX
* scaleY

**To Reproduce**

Using the following OpenAPI document:

```yaml
openapi: 3.0.3
info:
  title: Spectral evidence
  description: Noddy API to use in Spectral ticket
  version: 0.0.1
paths:
  /:
    get:
      responses:
        "200":
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  coordinateX:
                    type: string
                  scaleY:
                    type: string
```

And the following ruleset:

```yaml
extends: spectral:oas
rules:
  operation-operationId: off
  oas3-api-servers: off
  info-contact: off
  operation-description: off
  operation-tags: off
  camel-case-enforcement:
    message: "Property is not named in lower camel case: {{path}}, {{property}}"
    severity: error
    given: $..[?(@.type === 'object' && @.properties)].properties.*~
    then:
      function: casing
      functionOptions:
        type: camel
```

Executing Spectral gives the following output:

```bash
➜  spectral-evidence spectral lint --ruleset ./evidence.yaml openapi.yaml
OpenAPI 3.x detected

/Users/chris/Documents/git/github/spectral-evidence/openapi.yaml
 22:31  error  camel-case-enforcement  Property is not named in lower camel case: #/paths/~1/get/responses/200/content/application~1json/schema/properties/coordinateX, coordinateX  paths./.get.responses[200].content.application/json.schema.properties.coordinateX
 24:26  error  camel-case-enforcement  Property is not named in lower camel case: #/paths/~1/get/responses/200/content/application~1json/schema/properties/scaleY, scaleY            paths./.get.responses[200].content.application/json.schema.properties.scaleY

✖ 2 problems (2 errors, 0 warnings, 0 infos, 0 hints)

➜  spectral-evidence
```

I think this is the root of the issue: [here](https://github.com/stoplightio/spectral/blob/develop/src/functions/casing.ts#L26) - [HIDDEN]

**Expected behavior**

The ruleset should not raise the camel-case-enforcement errors as semantically the property names are correct.

**Environment:**
 - Node version: 12.20.0
 - Library version: 5.7.2
 - OS: macOs Catalina 10.15.7

### Additional contract requirements

- The built-in `casing` function with `type: camel` must accept camel-cased names ending in a single uppercase letter, including `coordinateX` and `scaleY`, without reporting them as invalid.

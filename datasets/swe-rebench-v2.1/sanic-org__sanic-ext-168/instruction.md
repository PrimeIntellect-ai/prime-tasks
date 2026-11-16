[Bug] When Pydantic model refers to another model, swagger errors out and redoc crashes with an error
**Describe the bug**
Invalid openapi spec is created when nested models are present in Pydantic models.

**Screenshots**
Redoc error:
![image](https://user-images.githubusercontent.com/22248828/203652682-b41c0b46-8b6e-493d-a503-0198164cb891.png)

SwaggeUI error:
![image](https://user-images.githubusercontent.com/22248828/203652720-1b57ef7d-9def-484b-b212-dfc3b4d3a1d4.png)

**To Reproduce**
Create an endpoint having a response set by Pydantic
```py
from pydantic import BaseModel
from datetime import datetime

class Alert(BaseModel):
    hit: dict[str, Any]
    last_updated: datetime

class AlertResponse(BaseModel):
    alert: Alert
    rule_id: str

...
@openapi.definition(
    response={'application/json': AlertResponse.schema()}
)
def get_alert(request: Request) -> HTTPResponse:
...
```

The resulting openapi spec is:
```yaml
openapi: 3.0.3
info:
  title: Test API
  version: 0.0.1
paths:
  /api/v1/alerts/{id}:
    get:
      operationId: get~alerts.get_alert
      summary: Get Alert
      tags:
        - alerts
      parameters:
        - name: id
          schema:
            type: string
          required: true
          in: path
      responses:
        default:
          content:
            application/json:
              schema:
                title: AlertResponse
                type: object
                properties:
                  alert:
                    $ref: '#/definitions/Alert'
                  rule_id:
                    title: Rule Id
                    type: string
                required:
                  - alert
                definitions:
                  Alert:
                    title: Alert
                    type: object
                    properties:
                      hit:
                        title: Hit
                        type: object
                      last_updated:
                        title: Last Updated
                        type: string
                        format: date-time
                    required:
                      - hit
                      - last_updated
          description: Default Response
tags:
  - name: alerts
```

And should be

```diff
openapi: 3.0.3
info:
  title: Test API
  version: 0.0.1
+definitions:
+  Alert:
+    title: Alert
+    type: object
+    properties:
+      hit:
+        title: Hit
+        type: object
+      last_updated:
+        title: Last Updated
+        type: string
+        format: date-time
+    required:
+      - hit
+      - last_updated
paths:
  /api/v1/alerts/{id}:
    get:
      operationId: get~alerts.get_alert
      summary: Get Alert
      tags:
        - alerts
      parameters:
        - name: id
          schema:
            type: string
          required: true
          in: path
      responses:
        default:
          content:
            application/json:
              schema:
                title: AlertResponse
                type: object
                properties:
                  alert:
                    $ref: '#/definitions/Alert'
                  rule_id:
                    title: Rule Id
                    type: string
                required:
                  - alert
-               definitions:
-                 Alert:
-                   title: Alert
-                   type: object
-                   properties:
-                     hit:
-                       title: Hit
-                       type: object
-                     last_updated:
-                       title: Last Updated
-                       type: string
-                       format: date-time
-                   required:
-                     - hit
-                     - last_updated
          description: Default Response
tags:
  - name: alerts
```

Putting it in https://editor.swagger.io/ also points out the errors in the spec

**Expected behavior**
For definitions to be placed at the root level of the spec

**Environment (please complete the following information):**
```
Sanic v22.9.1
mode: debug, single worker
server: sanic, HTTP/1.1
python: 3.10.5
platform: Linux-5.4.0-113-generic-x86_64-with-glibc2.28
auto-reload: enabled
packages: sanic-routing==22.8.0, sanic-ext==22.9.1
```

**Additional context**
Digging a bit, it seems like it makes sense this error happens since Pydantic does not have access to the greater openapi spec to add it's global definitions.

Would be great if there's a way to have it fixed without adding any openapi function calls, but I think a possible solution would be to add definitions from Pydantic schema models to the root of the spec via a function call, `openapi.add_definition(Alert)`?

### Additional contract requirements

The fix is exposed through the public `Component(model_class)` helper, which is
also exported as `sanic_ext.openapi.Component`.

- `Component(model_class)` returns a component reference of the form
  `{"$ref": "#/components/schemas/<ModelName>"}`.
- It registers `<ModelName>` under `components/schemas` in the generated
  specification.
- For a Pydantic model (a `pydantic.BaseModel` subclass or a Pydantic
  dataclass), the registered component is the model's JSON schema. Any nested
  `definitions` present in that schema are moved to the top level of
  `components/schemas`, so that nested `$ref`s resolve.
- The corrected specification is obtained by passing the model class to
  `Component` (for example
  `response={"application/json": openapi.Component(AlertResponse)}`), rather
  than by passing `Model.schema()` directly.

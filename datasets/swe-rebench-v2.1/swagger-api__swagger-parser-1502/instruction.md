Component schemas with same name are ignored after the second one
When several referenced schemas have the same name but different definitions, only the first two are created in components/schemas, the rest are ignored.
### base.yaml
```
openapi: 3.0.0
paths:
  /endpoint:
    post:
      summary: test summary
      description: test desc
      requestBody:
        required: true
        content:
          application/json:
            schema:
              oneOf:
                - $ref: 'config.yaml#/POST.type1/body'
                - $ref: 'config.yaml#/POST.type2/body'
                - $ref: 'config.yaml#/POST.type3/body'
                - $ref: 'config.yaml#/POST.type4/body'
      responses:
        '200':
          description: OK
```
### config.yaml
```
POST.type1:
  body:
    type: object
    additionalProperties: false
    properties:
      prop1:
        description: prop1
        type: boolean
POST.type2:
  body:
    type: object
    additionalProperties: false
    properties:
      prop2:
        description: prop2
        type: boolean
POST.type3:
  body:
    type: object
    additionalProperties: false
    properties:
      prop3:
        description: prop3
        type: boolean
POST.type4:
  body:
    type: object
    additionalProperties: false
    properties:
      prop3:
        description: prop3
        type: boolean
```
### main.java
```
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.parser.core.models.ParseOptions;

public class Main {

    public static void main(String[] args) {
        ParseOptions options = new ParseOptions();
        options.setResolve(true);
        OpenAPI openAPI = new OpenAPIV3Parser().read("base.yaml", null, options);
        System.out.println(openAPI.getComponents().getSchemas().keySet());
    }
}
```
### Result
```
[body, body_2]
```
### Expected result
```
[body, body_1, body_2]
```
Note: In this case 3 schemas are expected since `POST.type3.body` and `POST.type4.body` have the same definition.

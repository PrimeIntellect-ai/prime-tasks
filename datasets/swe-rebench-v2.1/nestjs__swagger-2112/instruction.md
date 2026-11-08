When using enableVersioning missing requestBody in document
### Is there an existing issue for this?

- [X] I have searched the existing issues

### Current behavior

When using nestJs enableVersioning:

```
app.enableVersioning({
        defaultVersion: ['1', '2'],
        type: VersioningType.URI,
    });
```

And creating the document:

```
    const builder = new DocumentBuilder()
        .setTitle('Some API')
        .setVersion('1')
        .setDescription('This is a test swagger doc');
    const document = SwaggerModule.createDocument(app, builder.build(), {
      operationIdFactory: (controllerKey: string, methodKey: string) => methodKey,
    });

    // missing responseBody in each version
    console.log(JSON.stringify(document, null, 2));
```

requestBody is only available on the first version in the list /v1/example and NOT on /v2/example:


```
{
  "openapi": "3.0.0",
  "paths": {
    "/v1/example": {
      "post": {
        "operationId": "postHello",
        "summary": "",
        "description": "Some api operation to post hello",
        "parameters": [],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/HelloDto"
              }
            }
          }
        },
        "responses": {
          "201": {
            "description": ""
          }
        }
      }
    },
    "/v2/example": {
      "post": {
        "operationId": "postHello",
        "summary": "",
        "description": "Some api operation to post hello",
        "parameters": [],
        "responses": {
          "201": {
            "description": ""
          }
        }
      }
    }
  },
  "info": {
    "title": "Some API",
    "description": "This is a test swagger doc",
    "version": "1",
    "contact": {}
  },
  "tags": [],
  "servers": [],
  "components": {
    "schemas": {
      "HelloDto": {
        "type": "object",
        "properties": {
          "someProperty": {
            "type": "string",
            "description": "some property",
            "example": "pm_1DkAUlB70neqlGn3zQESm7pl"
          },
          "someOtherProperty": {
            "type": "string",
            "description": "some other property",
            "example": "pm_1DkAUlB70neqlGn3zQESm7pl"
          }
        }
      }
    }
  }
}

```



### Minimum reproduction code

https://github.com/getlabs-sean/nestjs-swaggerjs-enableVersioning-issue

### Steps to reproduce

1) `yarn install`
2) `yarn nest start`
3) see document dumped in console.log

### Expected behavior

We use code that separates the openapi.json file into versions and if the requestBody is not in each endpoint path we have broken documentation.

### Package version

^5.2.1

### NestJS version

^8.0.0

### Node.js version

_No response_

### In which operating systems have you tested?

- [X] macOS
- [ ] Windows
- [ ] Linux

### Other

_No response_

### Additional contract requirements

- When versioning produces multiple route variants for a body-bearing endpoint, the generated OpenAPI document must include the request body on every variant, including variants from an array of default versions and controller-declared versions, including a neutral (no-version) variant.

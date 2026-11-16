InternalizeRefs does not internalize parameters of paths
Calling `.InternalizeRefs` on a schema that contains parameters on the path level does not seem to resolve those parameters correctly. The resulting schema still contains the reference to the external file. When moving the parameters below the operation level, the behavior is as expected.

<details>
  <summary>Schema</summary>

  ```yaml
  openapi: 3.0.0
  info:
    title: foo
    version: 0.0.0
  paths:
    /{external1}:
      parameters:
        - in: path
          name: external1
          required: true
          schema:
            $ref: './components.yaml#/components/schemas/External1'
      get:
        responses:
          '204':
            description: No content
  ```
</details>

<details>
  <summary>components.yaml</summary>

  ```yaml
  components:
    schemas:
      External1:
        type: string
  ```
</details>

<details>
  <summary>Code</summary>

  ```go
  package main

  import (
    "context"
    "encoding/json"
    "log"
    "os"

    "github.com/getkin/kin-openapi/openapi3"
  )

  func main() {
    loader := openapi3.NewLoader()
    loader.IsExternalRefsAllowed = true
    doc, err := loader.LoadFromFile("openapi.yaml")
    if err != nil {
      log.Fatalf("load: %v", err)
    }

    doc.InternalizeRefs(context.Background(), nil)

    result, err := json.MarshalIndent(doc, "", "  ")
    if err != nil {
      log.Fatalf("marshal: %v", err)
    }

    err = os.WriteFile("result.json", result, 0644)
    if err != nil {
      log.Fatalf("result: %v", err)
    }
  }
  ```
</details>

<details>
  <summary>Expected</summary>

  ```json
  {
    "components": {
      "schemas": {
        "External1": {
          "type": "string"
        }
      }
    },
    "info": {
      "title": "foo",
      "version": "0.0.0"
    },
    "openapi": "3.0.0",
    "paths": {
      "/{external1}": {
        "get": {
          "responses": {
            "204": {
              "description": "No content"
            }
          }
        },
        "parameters": [
          {
            "in": "path",
            "name": "external1",
            "required": true,
            "schema": {
              "$ref": "#/components/schemas/External1"
            }
          }
        ]
      }
    }
  }
  ```
</details>

<details>
  <summary>Got</summary>

  ```json
  {
    "info": {
      "title": "foo",
      "version": "0.0.0"
    },
    "openapi": "3.0.0",
    "paths": {
      "/{external1}": {
        "get": {
          "responses": {
            "204": {
              "description": "No content"
            }
          }
        },
        "parameters": [
          {
            "in": "path",
            "name": "external1",
            "required": true,
            "schema": {
              "$ref": "./components.yaml#/components/schemas/External1"
            }
          }
        ]
      }
    }
  }
  ```
</details>

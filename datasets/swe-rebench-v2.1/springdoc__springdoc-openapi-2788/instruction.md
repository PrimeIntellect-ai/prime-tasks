Nested fields in ParameterObject do not take into account annotations on parent classes
## Describe the bug

For a `@ParameterObject` annotated value, any annotations on the fields of the target class are not taken into account when creating the flattened values for the parameters. I believe this leads to 3 types or incorrect definitions being produced:

### Hidden parent fields
When a field in the `@ParameterObject` class is defined as hidden, or any subfields are hidden, those fields and any child fields should not included in the generated schema.

For the following endpoint definition and model
```java
    @GetMapping("/hidden-parent")
    public void nestedParameterObjectWithHiddenParentField(@ParameterObject ParameterObjectWithHiddenField parameters) {

    }

    public record ParameterObjectWithHiddenField(
        @Schema(hidden = true) NestedParameterObject schemaHiddenNestedParameterObject,
        @Parameter(hidden = true) NestedParameterObject parameterHiddenNestedParameterObject,
        NestedParameterObject visibleNestedParameterObject
    ) {

    }

    public record NestedParameterObject(
        String parameterField) {
    }
```

I'd expect the `schemaHiddenNestedParameterObject` and `parameterHiddenNestedParameterObject` fields, plus any child fields, to be excluded from the generated result, e.g.

```json
      "parameters": [
          {
            "name": "visibleNestedParameterObject.parameterField",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            }
          }
        ]
```
but they're currently included, e.g.
```json
      "parameters": [
          {
            "name": "schemaHiddenNestedParameterObject.parameterField",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "parameterHiddenNestedParameterObject.parameterField",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "visibleNestedParameterObject.parameterField",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            }
          }
        ]
```

### Renamed parent fields
Where a field in the `@ParameterObject` is specifically given a name through an appropriate annotation, this name should be applied in the flattened definition, but the field name as defined in the code is currently used.

For the following endpoint definition and model
```java
    @GetMapping("/renamed-parent")
    public void nestedParameterObjectWithRenamedParentField(@ParameterObject ParameterObjectWithRenamedField parameters) {

    }

    public record ParameterObjectWithRenamedField(
        @Schema(name = "schemaRenamed") NestedParameterObject schemaRenamedNestedParameterObject,
        @Parameter(name = "parameterRenamed") NestedParameterObject parameterRenamedNestedParameterObject,
        NestedParameterObject originalNameNestedParameterObject
    ) {

    }

    public record NestedParameterObject(
        String parameterField) {
    }
```
I'd expect the `schemaRenamedNestedParameterObject` and `parameterRenamedNestedParameterObject` to be given the names from the annotation in the resulting definition, e.g.
```json
        "parameters": [
          {
            "name": "schemaRenamed.parameterField",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "parameterRenamed.parameterField",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "originalNameNestedParameterObject.parameterField",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            }
          }
        ]
```
but the original field names are used, e.g.
```json
        "parameters": [
          {
            "name": "schemaRenamedNestedParameterObject.parameterField",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "parameterRenamedNestedParameterObject.parameterField",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "originalNameNestedParameterObject.parameterField",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            }
          }
        ]
```

###  Mandatory parameters in non-mandatory parent fields
Where a fields is marked as required (or resolves as required for a RequiredMode.AUTO annotation), but the parent fields is not required, that child field would not be mandatory within the request. There is a challenge here that the field would be required if any of the other fields from the parent are set, but there's no way of defining that in a flattened structure, so the definition should default to not forcing a field that's only conditionally required.

Given the following endpoint and model
```java
    @GetMapping("/optional-parent")
    public void nestedParameterObjectWithOptionalParentField(@ParameterObject ParameterObjectWithOptionalField parameters) {

    }

    public record ParameterObjectWithOptionalField(
        @Schema(requiredMode = Schema.RequiredMode.NOT_REQUIRED) NestedRequiredParameterObject schemaNotRequiredNestedParameterObject,
        @Parameter NestedRequiredParameterObject parameterNotRequiredNestedParameterObject,
        @Parameter(required = true) NestedRequiredParameterObject requiredNestedParameterObject
    ) {

    }

    public record NestedRequiredParameterObject(
        @Schema(requiredMode = Schema.RequiredMode.REQUIRED) String requiredParameterField) {
    }
```
I'd expect the fields makes as REQUIRED on an object that isn't set as REQUIRED to be shown as not required in the flattened definition, e.g.
```json
        "parameters": [
          {
            "name": "schemaNotRequiredNestedParameterObject.requiredParameterField",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "parameterNotRequiredNestedParameterObject.requiredParameterField",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "requiredNestedParameterObject.requiredParameterField",
            "in": "query",
            "required": true,
            "schema": {
              "type": "string"
            }
          }
        ]
```
but the definition currently only takes into account the child element annotations to treats the fields as required, e.g.
```json
        "parameters": [
          {
            "name": "schemaNotRequiredNestedParameterObject.requiredParameterField",
            "in": "query",
            "required": true,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "parameterNotRequiredNestedParameterObject.requiredParameterField",
            "in": "query",
            "required": true,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "requiredNestedParameterObject.requiredParameterField",
            "in": "query",
            "required": true,
            "schema": {
              "type": "string"
            }
          }
        ]
```

## Additional Information
* The version of Spring Boot being used does not seem to have any impact. The above examples were generated using 3.4.0 and the latest SNAPSHOT of springdoc-openapi from e8de90ee6b33cfb9a1c8539294a645b82d00a51d on the `main` branch.

### Additional contract requirements

- A field marked hidden at any depth of a parameter object is omitted from the flattened parameters together with all of its nested fields, not only when it sits directly under the top-level parameter object.
- A flattened child parameter that has no explicit requiredness is required only when its parent parameter is required. When the parent is optional, the child stays optional even if it carries a not-null annotation; when the parent is required, such a child is required.

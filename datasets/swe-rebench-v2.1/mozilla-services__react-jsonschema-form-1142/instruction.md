Recursive references are not supported
### Prerequisites

- [x] I have read the [documentation](https://github.com/mozilla-services/react-jsonschema-form/blob/master/README.md#readme);
- [x] In the case of a bug report, I understand that providing a [SSCCE](http://sscce.org/) example is tremendously useful to the maintainers.

### Description

Recursive references are not supported.

### Steps to Reproduce

1. Define a schema that utilises recursive referencing:
    ```json
    {
      "definitions": {
        "bar": { "$ref": "#/definitions/qux" },
        "qux": { "type": "string" }
      },
      "type": "object",
      "properties": {
        "foo": {
          "$ref": "#/definitions/bar"
        }
      }
    }
    ```

    or

    ```json
    {
      "definitions": {
        "testdef": { "$ref": "#/definitions/bar" },
        "bar": {
          "type": "object",
          "properties": {
            "qux": { "type": "string" }
          }
        }
      },
      "type": "object",
      "properties": {
        "foo": { "$ref": "#/definitions/testdef/properties/qux" }
      }
    }
    ```
2. Attempt to create a form using those schema.

#### Expected behavior

Form to be rendered.

#### Actual behavior

In the first case above ([shared playground link](https://mozilla-services.github.io/react-jsonschema-form/#eyJmb3JtRGF0YSI6e30sInNjaGVtYSI6eyJkZWZpbml0aW9ucyI6eyJiYXIiOnsiJHJlZiI6IiMvZGVmaW5pdGlvbnMvcXV4In0sInF1eCI6eyJ0eXBlIjoic3RyaW5nIn19LCJ0eXBlIjoib2JqZWN0IiwicHJvcGVydGllcyI6eyJmb28iOnsiJHJlZiI6IiMvZGVmaW5pdGlvbnMvYmFyIn19fSwidWlTY2hlbWEiOnt9fQ==)), a form is rendered—but where the field is expected, the following message appears:

> **Unsupported field schema { "$ref": "#/definitions/qux" }**

In the second case above ([shared playground link](https://mozilla-services.github.io/react-jsonschema-form/#eyJmb3JtRGF0YSI6e30sInNjaGVtYSI6eyJkZWZpbml0aW9ucyI6eyJ0ZXN0ZGVmIjp7IiRyZWYiOiIjL2RlZmluaXRpb25zL2JhciJ9LCJiYXIiOnsidHlwZSI6Im9iamVjdCIsInByb3BlcnRpZXMiOnsicXV4Ijp7InR5cGUiOiJzdHJpbmcifX19fSwidHlwZSI6Im9iamVjdCIsInByb3BlcnRpZXMiOnsiZm9vIjp7IiRyZWYiOiIjL2RlZmluaXRpb25zL3Rlc3RkZWYvcHJvcGVydGllcy9xdXgifX19LCJ1aVNjaGVtYSI6e319)), no form is rendered.  Console shows:

> **Error: Could not find a definition for #/definitions/testdef/properties/qux.**

### Version

0.46.0

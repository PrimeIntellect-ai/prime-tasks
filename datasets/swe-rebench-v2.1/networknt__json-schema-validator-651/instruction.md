Support BinaryNode
When using a Java data model with a byte[] property, json-schema-validator fails to validate because of an unknown data type.

Example:

Java model:
```java
public class Model {

      @ApiModelProperty(name = "s", value = "BASE64 encoded signature", required = true)
    private byte[] signature;
}
````
Jackson converts byte[] automatically to BASE64 strings.

JSON schema:
````json
{
  "properties": {
      "s": {
        "$id": "#/properties/s",
        "type": "string"
      }
  }
}
````

JSON file:
````json
{
  "s": "BASE64 string"
}
````

When parsing it using jackson using the Java model (with byte[] type) and then validating it, the resulting node in the jackson tree is of type BinaryTree. Validation fails then with an unknown type is not of type string error.
IMPORTANT to reproduce: Do not use jackson to directly parse into a tree. In this case the resulting jackosn node is of type TextNode and validation works fine.

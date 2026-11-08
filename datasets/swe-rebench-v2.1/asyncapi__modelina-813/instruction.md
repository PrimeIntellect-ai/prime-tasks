Java generator always adds @Json annotations for enums
@micro-jumbo commented on [Thu Jul 14 2022](https://github.com/asyncapi/spec/issues/822)

### Describe the bug
Java generator always adds @Json annotations for enums

### To Reproduce
For document:
```json
{
  "asyncapi": "2.3.0",
  "id": "urn:my:service",
  "defaultContentType": "application/json",
  "info": {
    "title": "My services",
    "version": "1.0.0"
  },
  "channels": {
    "accepted": {
      "subscribe": {
        "message": {
          "name": "SuccessMessage",
          "title": "SuccessMessage",
          "payload": {
            "type": "object",
            "title": "SuccessMessage",
            "properties": {
              "result": {
                "title": "SuccessMessageResult",
                "type": "string",
                "const": "SUCCESS"
              },
              "message": {
                "type": "string",
                "title": "SuccessMessageMessage"
              }
            },
            "required": [
              "result"
            ],
            "additionalProperties": false
          }
        }
      }
    }
  }
}
```

and generator:
```javascript
const generator = new JavaGenerator({
  collectionType: "List",
});
```

generated `SuccessMessageMessage` `enum` contains Jackson annotations (`@JsonValue` and `@JsonCreator`), but it shouldn't:
```java
import com.fasterxml.jackson.annotation.*;

public enum SuccessMessageResult {
  SUCCESS("SUCCESS");

  private String value;

  SuccessMessageResult(String value) {
    this.value = value;
  }

  @JsonValue
  public String getValue() {
    return value;
  }

  @Override
  public String toString() {
    return String.valueOf(value);
  }

  @JsonCreator
  public static SuccessMessageResult fromValue(String value) {
    for (SuccessMessageResult e : SuccessMessageResult.values()) {
      if (e.value.equals(value)) {
        return e;
      }
    }
    throw new IllegalArgumentException("Unexpected value '" + value + "'");
  }
}
```

These should be generated only when Jackson annotations are enabled.


---

@github-actions[bot] commented on [Thu Jul 14 2022](https://github.com/asyncapi/spec/issues/822#issuecomment-1184728142)

Welcome to AsyncAPI. Thanks a lot for reporting your first issue. Please check out our [contributors guide](https://github.com/asyncapi/community/blob/master/CONTRIBUTING.md) and the instructions about a [basic recommended setup](https://github.com/asyncapi/.github/blob/master/git-workflow.md) useful for opening a pull request.<br />Keep in mind there are also other channels you can use to interact with AsyncAPI community. For more details check out [this issue](https://github.com/asyncapi/asyncapi/issues/115).

### Additional contract requirements

- In generated enum source, render the `fromValue` factory before the `toString` method.

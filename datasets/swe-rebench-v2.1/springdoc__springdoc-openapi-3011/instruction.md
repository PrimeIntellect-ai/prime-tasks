Type-use annotations are not picked up when used in defining parameters
I have a use case in which I am using type-use annotations for parameters.
Take following example:

```java
    @PostMapping("euroMillions")
    public ResponseEntity<String> euroMillions(@Parameter(description = "the numbers")
                                               @RequestParam @Size(min = 5, max = 5) List<@Max(50) @Min(1) Integer> numbers,
                                               @Parameter(description = "the stars")
                                               @RequestParam @Size(min = 2, max = 2) List<@Max(12) @Min(1) Integer> stars) {
        return ResponseEntity.ok("ok");
    }
```

I am expecting to see the `@Max` and `@Min` translated to maximum and minimum properties in the Openapi-definition, but instead it translates to:

```json
        "parameters": [
          {
            "name": "numbers",
            "in": "query",
            "description": "the numbers",
            "required": true,
            "schema": {
              "type": "array",
              "items": {
                "type": "integer",
                "format": "int32",
>>>> maximum and minimum properties are missing
              },
              "maxItems": 5,
              "minItems": 5
            }
          },
          {
            "name": "stars",
            "in": "query",
            "description": "the stars",
            "required": true,
            "schema": {
              "type": "array",
              "items": {
                "type": "integer",
                "format": "int32",
>>>> maximum and minimum properties are missing
              },
              "maxItems": 2,
              "minItems": 2
            }
          }
        ]
```

If I move away from the parameters and make a RequestBody like so:

```java
    @PostMapping("euroMillions2")
    public ResponseEntity<String> euroMillions2(@RequestBody LotteryTicket lotteryTicket) {
        return ResponseEntity.ok("ok");
    }
```
```java
public class LotteryTicket {

    @Size(min = 5, max = 5)
    private List<@Max(50) @Min(1) Integer> numbers;

    @Size(min = 2, max = 2)
    private List<@Max(12) @Min(1) Integer> stars;
}
```
The definition is correctly processed and the minimum and maximum properties are set for the lotteryTicket-schema:
```json
  "components": {
    "schemas": {
      "LotteryTicket": {
        "type": "object",
        "properties": {
          "numbers": {
            "type": "array",
            "items": {
              "type": "integer",
              "format": "int32",
              "maximum": 50,
              "minimum": 1
            },
            "maxItems": 5,
            "minItems": 5
          },
          "stars": {
            "type": "array",
            "items": {
              "type": "integer",
              "format": "int32",
              "maximum": 12,
              "minimum": 1
            },
            "maxItems": 2,
            "minItems": 2
          }
        }
      }
    }
  }
```

I tested this on the latest snapshot-version of springdoc: 2.8.9-SNAPSHOT

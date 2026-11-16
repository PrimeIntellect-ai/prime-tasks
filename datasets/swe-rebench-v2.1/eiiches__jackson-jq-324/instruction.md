Add uuid5 in "jackson-jq/extras" module
Usage example:

```jq
import "jackson-jq/extras" as extras;
"name" | extras::uuid5("2eb04e17-176e-4ba1-95b5-05834ca864d7") # => 52f527cc-e264-50b3-9bb1-15917606a90e
```

`uuid5` will not be imported in the root scope (as opposed to `uuid4`, which is imported to the root scope automatically if the jar is present on the classpath).

JSON-B transient and property annotation collide unexpectedly
Originally raised by @sdaschner in these issues:
OpenLiberty: https://github.com/OpenLiberty/open-liberty/issues/13640
Quarkus: https://github.com/quarkusio/quarkus/issues/11594

**Describe the bug**
When mapping a class via JSON-B, and annotating fields as follows, the result throws an error because of mismatching types:

```java
public class Coffee {

    @JsonbTransient
    private Order order;

    @JsonbProperty("order")
    private URI orderLink;

    Coffee() {
        order = new Order();
        orderLink = URI.create("http://localhost/");
    }

    // getters & setters
}
```

this results in:

```
[ERROR   ] Unable to serialize property 'order' from com.sebastian_daschner.openliberty.Coffee
[ERROR   ] Generating incomplete JSON
[ERROR   ] Problem with writing the data, class com.sebastian_daschner.openliberty.Coffee, ContentType: application/json
```

If both properties `order` and `orderLink` have the same type, it works as expected (i.e. `orderLink` is serialized as `"order"`).

However, if we annotate `@JsonbProperty` on the setter instead, it works:

```java
public class Coffee {

    @JsonbTransient
    private Order order;

    private URI orderLink;

    // [...]

    @JsonbProperty("order")
    public URI getOrderLink() {
        return orderLink;
    }

}
```

Response:

```json
{"order":"http://localhost/"}
```

There seems to be an unexpected type link of the (ignored) property with the default serialized JSON key `"order"`, and the custom name binding.

**To Reproduce**
See code snippets in description

**Expected behavior**
Original code should deserialize into the expected JSON of:
```json
{"order":"http://localhost/"}
```
instead of throwing an error

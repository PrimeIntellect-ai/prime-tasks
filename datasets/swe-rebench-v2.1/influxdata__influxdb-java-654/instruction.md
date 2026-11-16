Lack of Point.Builder#addField(String, int) causes unexpected result
I have a data class that looks kind of like this:

```java
@Measurement(name = "myMeasurement")
public class MyMeasurement {

    @Column(name = "myField")
    private int myField;

    // ... accessors, constructors, etc
}
```

In my application, I'm constructing points like this:

```java
Point point = Point.measurementByPOJO(MyMeasurement.class)
        .addFieldsFromPOJO(someMeasurement)
        .build();
```

In my unit tests, I'm trying to verify that my InfluxDB client is called with the right parameters:

```java
@Test
public void myMethod_callsInfluxWithCorrectPoint() {
    // ... setup and calling my method
    int value = 15;
    Point expected = Point.measurement("myMeasurement")
            .addField("myField", 15)
            .build();
    verify(mockInfluxDb).write(expected);
}
```

This test fails saying that the expected arguments don't match the actual arguments, but the serialization of the `Point`s look identical. What's going on is that my `int` parameter is being coerced to match the `addField(String, long)` overload, so the field is being stored as `Long`, and then `verify()` fails because of the type mismatch.

Ultimately, I worked around this by declaring `value` as `Integer` so that the `addField(String, Number)` overload was used. But I spent a lot of time spinning my wheels trying to understand why the test was failing.

### What to do

* Should there be an `addField(String, int)` (and other primitive numeric types)?
* Should users just stick to `long` or `double` for all numeric fields?

### Additional contract requirements

Primitive `int` values passed to `Point.Builder.addField` must be stored consistently with the equivalent primitive value extracted from a POJO, so the resulting points compare equal. The same consistency is required for primitive `short` and `float` values, whose overload selection otherwise stores a different numeric type.

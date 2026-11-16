Deserializing a java.sql.Timestamp returns a java.util.Date
Hello !
I'm using Yasson 1.0.3 on Java 11 and deserializing a java.sql.Timestamp returns a java.util.Date instead of a Timestamp.

For instance, this test :
```java
    @Test
    public void testTimestamp() {
        Timestamp expectedTimestamp = Timestamp.from(Instant.now());

        Jsonb jsonb = new JsonBindingBuilder().build();
        String json = jsonb.toJson(expectedTimestamp);
        Timestamp timestamp = jsonb.fromJson(json, Timestamp.class);

        assertEquals(expectedTimestamp, timestamp);
    }
```

Will throw the following exception :
```
java.lang.ClassCastException: class java.util.Date cannot be cast to class java.sql.Timestamp (java.util.Date is in module java.base of loader 'bootstrap'; java.sql.Timestamp is in module java.sql of loader 'platform')

	at [snipped].YassonTest.testTimestamp(YassonTest.java:24)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:62)
	at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
	at java.base/java.lang.reflect.Method.invoke(Method.java:566)
```

It's even more problematic when you have a java.sql.Timestamp argument encapsulated in an object, as the full object can't be deserialized. It throws a `java.lang.IllegalArgumentException: argument type mismatch` exeption.

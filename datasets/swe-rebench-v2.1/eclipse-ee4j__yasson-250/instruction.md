ClassCastException when marshalling char[]
The test` org.eclipse.yasson.defaultmapping.collections.CollectionsTest#testMarshallArray` claims support for several arrays, including `char[]`.

Not all supported arrays are tested.

When adding a testcase using a `char[]`, the test fails with a `ClassCastException: [C cannot be cast to [Ljava.lang.Object;`

```
final char[] charArray = new char[] {'a', 'b', 'c'};
assertEquals("[\"a\",\"b\",\"c\"]", jsonb.toJson(charArray));
```

Observed with yasson 1.0.1 and reproduced in MASTER.

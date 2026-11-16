Implement equals for the ImmutableMetadata object
# Context
When working with an `ImmutableMetadata` it is hard to write tests because we cannot compare a `FlagEvaluationDetails` anymore.

```java
String flagKey = "bool_targeting_match";
FlagEvaluationDetails expected = FlagEvaluationDetails.builder()
        .reason(Reason.ERROR.toString())
        .value(false)
        .errorCode(ErrorCode.GENERAL)
        .errorMessage("impossible to contact GO Feature Flag relay proxy instance")
        .flagMetadata(ImmutableMetadata.builder().build())
        .build();
FlagEvaluationDetails<Boolean> got = goffClient.getBooleanDetails(flagKey, false, defaultEvaluationContext);
assertEquals(expected, got);
```

The JUNIT method `assertEquals` is comparing the reference of the object.

# Expected behavior
We should be able to use `assertEquals` for the whole `FlagEvaluationDetails` object.
For this we should probably implement the `equals()` method in the `ImmutableMetadata` object.

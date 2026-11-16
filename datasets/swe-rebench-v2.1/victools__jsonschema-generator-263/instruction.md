Map additionalProperties sometimes missing with interface value
Hi,

I have an issue with Maps wit Option.MAP_VALUES_AS_ADDITIONAL_PROPERTIES, when the Map Value type is
not a concrete class. In my case we use a custom subTypeResolver picking the concrete implementation from @JsonDeserialize or @JsonSerialize annotations. Using the concrete Impl (Map<String, BImpl>) works as expected.
Is there something I miss, or should the AdditionalPropertiesModule use the subTypeResolver as expected?

```java
@JsonSerialize(as = AImpl.class)
public interface A {
    Map<String, B> getMap();
}

@JsonSerialize(as = BImpl.class)
public interface B {
    String getName();
}
```

**Outcome**:
```json
"map" : {
  "type" : "object",
  "additionalProperties" : { }
},
```
**Expected**:
```json
"map" : {
  "type" : "object",
  "additionalProperties" : {
     "name": { "type": "string"}
   }
}
```

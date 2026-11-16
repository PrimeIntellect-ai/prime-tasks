Serializing an array of values in a JsonbSerializer fails when not chaining calls
**Describe the bug**
When defining a custom JsonbSerializer that writes an array of primitives, serializing will fail when not chaining calls that write the primitives.

**To Reproduce**
```
public class Yasson {
	public static class Dummy {
	}

	public static JsonbSerializer<Dummy> dummySerializerOK = new JsonbSerializer<>() {
		public void serialize(Dummy dummy, JsonGenerator out, SerializationContext ctx) {
			out.writeStartArray().write("abc").write("def").write("ghi").writeEnd();
		}
	};

	public static JsonbSerializer<Dummy> dummySerializerThatFails = new JsonbSerializer<>() {
		public void serialize(Dummy dummy, JsonGenerator out, SerializationContext ctx) {
			out.writeStartArray();
			out.write("abc");
			out.write("def");
			out.write("ghi");
			out.writeEnd();
		}
	};

	public static void main(String... args) {
		JsonbConfig cfg = new JsonbConfig().withSerializers(dummySerializerOK);
		Jsonb jsonb = JsonbBuilder.newBuilder().withConfig(cfg).build();
		System.out.println(jsonb.toJson(new Dummy()));
		System.out.println("----------");

		cfg = new JsonbConfig().withSerializers(dummySerializerThatFails);
		jsonb = JsonbBuilder.newBuilder().withConfig(cfg).build();
		System.out.println(jsonb.toJson(new Dummy()));
	}
}
```
**Stack trace**
```
[20:42:12 stephane_vallee] ~/dev/projects/nuts-platform $  cd /Users/stephane_vallee/dev/projects/nuts-platform ; /usr/bin/env /Library/Java/JavaVirtualMachines/jdk-17.0.2.jdk/Contents/Home/bin/java -XX:+ShowCodeDetailsInExceptionMessages @/var/folders/1x/ck69t7mx1fl7r1y9mhqq28980000gn/T/cp_cmtppnwhql5z07xz6qdg4tpr7.argfile com.nuts.Yasson
["abc","def","ghi"]
----------
Jun. 27, 2022 8:42:38 P.M. org.eclipse.yasson.internal.SerializationContextImpl marshall
SEVERE: Generating incomplete JSON
Exception in thread "main" jakarta.json.bind.JsonbException: write(String value) cannot be called outside of the scope of user generator.
        at org.eclipse.yasson.internal.serializer.YassonGenerator.writeValidate(YassonGenerator.java:212)
        at org.eclipse.yasson.internal.serializer.YassonGenerator.write(YassonGenerator.java:146)
        at com.nuts.Yasson$2.serialize(Yasson.java:26)
        at com.nuts.Yasson$2.serialize(Yasson.java:1)
        at org.eclipse.yasson.internal.serializer.UserDefinedSerializer.serialize(UserDefinedSerializer.java:35)
        at org.eclipse.yasson.internal.serializer.RecursionChecker.serialize(RecursionChecker.java:38)
        at org.eclipse.yasson.internal.serializer.KeyWriter.serialize(KeyWriter.java:41)
        at org.eclipse.yasson.internal.serializer.NullSerializer.serialize(NullSerializer.java:67)
        at org.eclipse.yasson.internal.SerializationContextImpl.serializeObject(SerializationContextImpl.java:197)
        at org.eclipse.yasson.internal.SerializationContextImpl.marshall(SerializationContextImpl.java:133)
        at org.eclipse.yasson.internal.SerializationContextImpl.marshall(SerializationContextImpl.java:159)
        at org.eclipse.yasson.internal.JsonBinding.toJson(JsonBinding.java:121)
        at com.nuts.Yasson.main(Yasson.java:39)
```

**Expected behavior**
Both serializers should output ["abc","def","ghi"]. Only the first one with chained method calls does.


**System information:**
 - OS: any
 - Java Version: 17
 - Yasson Version: 3.0.0

**Additional context**
[HIDDEN]

### Additional contract requirements

- A custom `JsonbSerializer` that writes an array of primitive strings must serialize successfully whether its `JsonGenerator` calls are chained or made as separate statements, producing the corresponding JSON array.
- `JsonGenerator.writeStartArray()` and `JsonGenerator.write(String value)` must return a `JsonGenerator` that can continue writing to the same in-progress JSON output, so subsequent calls can be chained. The returned generator need not be the same object instance.

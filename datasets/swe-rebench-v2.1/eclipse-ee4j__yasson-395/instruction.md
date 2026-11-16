Custom JsonbAdapter/JsonbSerializer not working on "known root types"
yasson:1.0.4 doesn't respect custom JsonbAdapter/JsonbSerializer on "known root types" anymore.

The outcome of the testcode below differs between yasson:1.0.2 and yasson:1.0.4

With yasson:1.0.2 all test pass
With yasson:1.0.4 the "adaptKnownRootType" test fails.

 I assume the problem came from the Marshaller change in PR 215 https://github.com/eclipse-ee4j/yasson/pull/215/files#diff-44d72b506105258cffab226412abc88bR129

```java
import org.junit.jupiter.api.Test;
import javax.json.Json;
import javax.json.JsonObject;
import javax.json.bind.JsonbBuilder;
import javax.json.bind.JsonbConfig;
import javax.json.bind.adapter.JsonbAdapter;

import static org.junit.jupiter.api.Assertions.assertEquals;

public class BugReport {

    /*
        This test passes while using yasson:1.0.2 but fails with yasson:1.0.4.
        I assume the problem came from the Marshaller change in PR 215
        https://github.com/eclipse-ee4j/yasson/pull/215/files#diff-44d72b506105258cffab226412abc88bR129
     */
    @Test
    void adaptKnownRootType() {
        String str = "Original";
        JsonbConfig jsonbConfig = new JsonbConfig().withAdapters(new StringAdapter());
        String json = JsonbBuilder.create(jsonbConfig).toJson(str, str.getClass());
        assertEquals("{\"str\":\"Adapted\"}", json.toString());
    }

    /*
        This test passes on yasson:1.0.2 and yasson:1.0.4, because the Adapter transforms an object which isn't a "Known Type".
     */
    @Test
    void adaptUnknownRootType() {
        SomeObject obj = new SomeObject();
        JsonbConfig jsonbConfig = new JsonbConfig().withAdapters(new SomeObjectAdapter());
        String json = JsonbBuilder.create(jsonbConfig).toJson(obj, obj.getClass());
        assertEquals("{\"obj\":\"Adapted\"}", json.toString());
    }

    static class StringAdapter implements JsonbAdapter<String, JsonObject> {
        @Override
        public JsonObject adaptToJson(String obj) {
            return Json.createObjectBuilder().add("str", "Adapted").build();
        }

        @Override
        public String adaptFromJson(JsonObject obj) throws Exception {
            return "";
        }
    }

    static class SomeObjectAdapter implements JsonbAdapter<SomeObject, JsonObject> {

        @Override
        public JsonObject adaptToJson(SomeObject obj) throws Exception {
            return Json.createObjectBuilder().add("obj", "Adapted").build();
        }

        @Override
        public SomeObject adaptFromJson(JsonObject obj) throws Exception {
            return new SomeObject();
        }
    }

    static class SomeObject {
    }

}
```

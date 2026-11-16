JSONObject constructors do not check for non-finite numbers
**Problem**
The constructors `org.json.JSONObject.JSONObject(Map<?, ?>)` and `org.json.JSONObject.JSONObject(Object)` do not check occuring numbers in values for finiteness and thus allow creating of invalid JSON object which then run into strange behaviour when stringifying.

The `Map` constructor even mentiones `@throws JSONException - If a value in the map is non-finite number.` but this exception can only occur here when a nested call throws it, e.g. a value with a `List` containing non-finite numbers.

**Code example**
```java
import static org.junit.jupiter.api.Assertions.assertThrows;
import java.util.Map;
import org.json.JSONException;
import org.json.JSONObject;
import org.junit.jupiter.api.Test;

class JSONObjectTest {
    @Test void jsonObject_map() {
        assertThrows(JSONException.class, () -> new JSONObject(Map.of("a", Double.POSITIVE_INFINITY)));
    }

    @Test void jsonObject_bean() {
        assertThrows(JSONException.class, () -> new JSONObject(new MyBean()));
    }
    public static class MyBean {
        public double getA() { return Double.POSITIVE_INFINITY; }
    }
}
```
Both tests fail and instead the constructors return an instance of a `JSONObject` with a key `"a"` mapped to a non-finite double.

**Cascading problems**
Calling `toString()` on the returned `JSONObject` will internally throw a `JSONException` in `toString(0)` while writing the non-finite value and this will be catched resulting in a `null` returned from the method. `obj.getDouble("a")` on the other hand will return the non-finite double.

**Idea**
[HIDDEN]

### Additional contract requirements

- Constructing a `JSONObject` from a map containing a non-finite number must throw `JSONException`.
- Constructing a `JSONObject` from a bean whose getter returns a non-finite number must throw `JSONException`.

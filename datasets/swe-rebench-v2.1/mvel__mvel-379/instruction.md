map == empty evaluates incorrectly in MVEL
**Summary**:
The `empty` keyword does not work correctly for `Map` in MVEL.
- `list == empty` correctly evaluates to `true`
- `map == empty` incorrectly evaluates to `false`, even when the map is actually empty.

**Reproducible Code**:
```java
import java.util.*;
import org.mvel2.MVEL;

public class MVELEmptyExample {
    public static void main(String[] args) {
        Map<String, Object> vars = new HashMap<>();
        vars.put("map", new HashMap<>());  // Empty map
        vars.put("list", new ArrayList<>()); // Empty list

        System.out.println("Is map empty? " + MVEL.eval("map == empty", vars)); // Expected: true, Actual: false
        System.out.println("Is list empty? " + MVEL.eval("list == empty", vars)); // Expected: true, Actual: true
    }
}
```
**Expected Behavior:**
map == empty should evaluate to true, just like list == empty.

**Actual Behavior**:
map == empty incorrectly evaluates to false, even when the map is empty.
However, map.isEmpty() works correctly.

**Version**:
MVEL Version: [2.5.2.Final]
Java Version: [21]

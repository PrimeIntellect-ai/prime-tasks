Anvil treats named imports as normal imports
Assume we have
```
import java.util.Date as Instant
import com.squareup.test.*
```
where the package `com.squareup.test` contains a `Date` class, then Anvil will resolve the class as `java.util.Date`. [HIDDEN]

### Additional contract requirements

- When resolving an unqualified `Date`, the aliased import `java.util.Date as Instant` must not cause `Date` to resolve to `java.util.Date`. If `com.squareup.test` contains a `Date` class, the wildcard import must allow `Date` to resolve to `com.squareup.test.Date`.

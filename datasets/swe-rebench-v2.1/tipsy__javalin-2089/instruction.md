Path Parameters Unavailable in beforeMatched
**Actual behavior (the bug)**
After upgrading to Javalin 6.0.0, when using the beforeMatched hook, ctx.pathParamMap() returns an empty map, and accessing named path parameters via ctx.pathParam("name") does not work as expected.

**Expected behavior**
The expected behavior is that within the beforeMatched hook, ctx.pathParamMap() and ctx.pathParam() should work as in the other normal route handlers.

**To Reproduce**
```kotlin
import io.javalin.Javalin
import io.javalin.apibuilder.ApiBuilder.get

fun main() {
    val app = Javalin.create { javalinConfig ->
        javalinConfig.router.apiBuilder {
            get("/{test}") {
                println("get: " + it.pathParamMap())
            }
        }
    }.start(7000)

    app.beforeMatched {
        println("before matched: " + it.pathParamMap())
    }
}
```
```
HTTP GET /test
before matched: {}
get: {test=test}
```

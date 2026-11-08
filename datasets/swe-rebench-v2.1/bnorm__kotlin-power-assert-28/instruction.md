Wrong vertical order of values of evaluated expressions in error output
Given:
```
        val foo = 7
        val bar = 2
        val expectedResult = 3
        assert(expectedResult == bar + foo)
```

Current output:
```
java.lang.AssertionError: Assertion failed
assert(expectedResult == bar + foo)
       |              |  |     |
       |              |  |     7
       |              |  9
       |              |  2
       |              false
       3

```

Instead `2` and `9` should be displayed vice versa.

Just in case following is my set-up:

```
plugins {
    id("com.android.application")
    kotlin("android")
    kotlin("kapt")
    kotlin("plugin.serialization") version "1.4.20"
    id("de.mannodermaus.android-junit5")
    id("com.bnorm.power.kotlin-power-assert") version ""0.6.0""
}
```

### Additional contract requirements

- For `var i = 1; assert(++i == 4)`, the assertion message must be exactly:
```
Assertion failed
assert(++i == 4)
       |   |
       |   false
       2
```
- Additionally, the assertion message for `var i = 1; assert(i++ == 4)` must be exactly:
```
Assertion failed
assert(i++ == 4)
       |   |
       |   false
       1
```

For `var i = 3; assert(--i == 4)`, the assertion message must be exactly:
```
Assertion failed
assert(--i == 4)
       |   |
       |   false
       2
```

For `var i = 3; assert(i-- == 4)`, the assertion message must be exactly:
```
Assertion failed
assert(i-- == 4)
       |   |
       |   false
       3
```
- For `assert(1.shl(1) == 4)`, the assertion message must be exactly:
```
Assertion failed
assert(1.shl(1) == 4)
         |      |
         |      false
         2
```

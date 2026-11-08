FileStructure rule doesn't fix incorrect order of kdoc and package directive
## Describe the bug
Consider the following code
```kotlin
package test.paragraph3.top_level

/**
 * Header Kdoc
 */

import org.cqfn.diktat.bar

class A {}
```
## Expected behavior
```kotlin
/**
 * Header Kdoc
 */

package test.paragraph3.top_level

import org.cqfn.diktat.bar

class A {}
```
## Observed behavior
**Nothing changed**

-----------
Note: This test is already created in diKTat and called `TopLevelWithHeaderKdocTest.kt`, but for now disabled

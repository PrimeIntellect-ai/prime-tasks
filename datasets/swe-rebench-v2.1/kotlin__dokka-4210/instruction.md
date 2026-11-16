'greater than' symbol is not rendered in large code blocks
**Describe the bug**
When using three-backticks block in the documentation, sign `>` is not rendered properly:

```
 * It is also an established pattern to validate input in user's classes in the following manner:
 * ```
 * @Serializable
 * class User(val age: Int, val name: String) {
 *     init {
 *         require(age > 0) { ... }
 *         require(name.isNotBlank()) { ... }
 *     }
 * }
 * ```
 * While clearly being serialization error (when compromised data was deserialized),
 *
```

<img width="1207" alt="image" src="https://github.com/user-attachments/assets/e1d65b08-5c06-4027-914c-0ff55ceff22c">

I also tried `&gt;`, but it is rendered literally as `&gt;` and not as `>`.

**Expected behaviour**
Sign `>` should be visible in the screenshot between `age` and `0`

**To Reproduce**
Reproducer also available here: https://kotlinlang.org/api/kotlinx.serialization/kotlinx-serialization-core/kotlinx.serialization/-serialization-exception/ (source: https://github.com/Kotlin/kotlinx.serialization/blob/79ecba6e813cc0d59758c9d3f229288b6bd90e8a/core/commonMain/src/kotlinx/serialization/SerializationExceptions.kt#L27)

**Dokka configuration**
Configuration of dokka used to reproduce the bug

```Kotlin
dokka = "1.9.20"
gradlePlugin-dokka = { module = "org.jetbrains.dokka:dokka-gradle-plugin", version.ref = "dokka"}
```

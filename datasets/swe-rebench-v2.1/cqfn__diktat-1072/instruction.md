Incorrect detection of Kdoc
If the method has any annotations - we won't be able to see the Kdoc. Easy fix

```
@ExperimentalFileSystem
/**
 * Simple file reading with okio (returning a list with strings)
 *
 * @param toml string with a path to a file
 * @return list with strings
 * @throws e FileNotFoundException if the toml file is missing
 */
internal fun readAndParseFile(toml: String): List<String> {
    try {
        val ktomlPath = toml.toPath()
        return FileSystem.SYSTEM.read(ktomlPath) {
            // FixMe: may be we need to read and at the same time parse (to make it parallel)
            generateSequence { readUtf8Line() }.toList()
        }
    } catch (e: FileNotFoundException) {
        println("Not able to find toml-file in the following path: $toml")
        throw e
    }
}
```

```
D:\ktoml\ktoml-file\src\commonMain\kotlin\com\akuleshov7\ktoml\file\FileUtils.kt:12:1: [MISSING_KDOC_TOP_LEVEL] all public and internal top-level classes and functions should have Kdoc
```

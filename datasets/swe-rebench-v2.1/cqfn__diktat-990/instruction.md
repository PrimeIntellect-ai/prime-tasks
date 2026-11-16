Kdoc generation for "throws exception"
```
    fun readAndParseFile(): TomlFile {
        try {
            val ktomlPath = toml.toPath()
            val ktomlLinesFromFile = FileSystem.SYSTEM.read(ktomlPath) {
                // FixMe: may be we need to read and at the same time parse (to make it parallel)
                generateSequence { readUtf8Line() }.toList()
            }
            return parseStringsToTomlNode(ktomlLinesFromFile)
        } catch (e: FileNotFoundException) {
            println("Not able to find toml-file in the following path: $toml")
            throw e
        }
    }
```

diktat fixes it with `     * @throws e` instead of  `  * @throws  FileNotFoundException`

### Additional contract requirements

When a method rethrows a caught exception parameter, its generated `@throws` tag must identify the exception by the declared type of that catch parameter, rather than by the parameter's variable name.

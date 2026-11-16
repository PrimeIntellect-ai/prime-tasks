Unable to generate files with Norwegian letters øåø
Hei, I have been trying to make fabrikt generate files with utf-8 encoding by passing file encoding to the file generation task but without luck. The files generated do not contain norwgian charactes øæå . Am I setting the encoding wrong ?

tasks {
    val generateCode by creating(JavaExec::class) {
        print(apiFile)
        inputs.files(apiFile)
        outputs.dir(generationDir)
        outputs.cacheIf { true }
        classpath(fabrikt)
        main = "com.cjbooms.fabrikt.cli.CodeGen"
        jvmArgs?.add("-Dfile.encoding=UTF-8")
        args = listOf(
            "--output-directory", generationDir,
            "--base-package", "xxxxxxxxx",
            "--api-file", apiFile,
            "--targets", "http_models",
            "--http-client-opts", "resilience4j"
        )
    }

### Additional contract requirements

- When converting `PascalCase_enumWith-ÅabcØæ-åØÆÅHij-special/characters.json` to an enum name, the result must be `PASCAL_CASE_ENUM_WITH_ÅABC_ØÆ_Å_ØÆÅHIJ_SPECIAL_CHARACTERS_JSON`.
- When `Åabc_øæå-ØÆÅ-hij` is converted to pascal case, the result must be `ÅabcØæåØÆÅHij`.

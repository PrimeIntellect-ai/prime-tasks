Support decoding of Map<String, List<String>>
> @orchestr7 any idea how can multiple list. list are many. so can not do specific variable for all list
>
> ```
> [bundles]
> koin-common = [
>     "koin-core",
>     "koin-compose",
>     "koin-compose-viewmodel"
> ]
>
> ktor-common = [
>     "ktor-client-core",
>     "ktor-client-content-negotiation",
>     "ktor-serialization-kotlinx-json",
>     "ktor-client-auth",
>     "ktor-client-logging"
> ]
>
> ktor-commond = [
>     "ktor-client-core",
>     "ktor-client-content-negotiation",
>     "ktor-serialization-kotlinx-json",
>     "ktor-client-auth",
>     "ktor-client-loggqing"
> ]
> ```
> i try this code for understanding how looks like but i not understand how can array extract
> ```
> val tomlString = """
> [bundles]
> koin-common = [
>     "koin-core",
>     "koin-compose",
>     "koin-compose-viewmodel"
> ]
>
> ktor-common = [
>     "ktor-client-core",
>     "ktor-client-content-negotiation",
>     "ktor-serialization-kotlinx-json",
>     "ktor-client-auth",
>     "ktor-client-logging"
> ]
>
> ktor-commond = [
>     "ktor-client-core",
>     "ktor-client-content-negotiation",
>     "ktor-serialization-kotlinx-json",
>     "ktor-client-auth",
>     "ktor-client-loggqing"
> ]
> """.trimIndent()
>
> val tomlAST = TomlParser(TomlInputConfig()).parseString(tomlString)
> tomlAST.prettyPrint()
>
> ```
>
> this is output
> ```
>  - TomlFile (rootNode)
>      - TomlTable ([bundles])
>          - TomlKeyValueArray (koin-common=[ "koin-core", "koin-compose", "koin-compose-viewmodel" ])
>          - TomlKeyValueArray (ktor-common=[ "ktor-client-core", "ktor-client-content-negotiation", "ktor-serialization-kotlinx-json", "ktor-client-auth", "ktor-client-logging" ])
>          - TomlKeyValueArray (ktor-commond=[ "ktor-client-core", "ktor-client-content-negotiation", "ktor-serialization-kotlinx-json", "ktor-client-auth", "ktor-client-loggqing" ])
>
> ```
> how can get bundles list data from tomlstring. any suggestion or solution. thank you
> ```
> @Serializable
> data class VersionCatalog(
>     val bundles: Map<String, List<String>> = emptyMap(),
> )
>
> private fun versionCatalog(tomlString: String): VersionCatalog =
>         Toml(
>             inputConfig = TomlInputConfig(
>                 ignoreUnknownNames = true,
>             )
>         ).decodeFromString<VersionCatalog>(tomlString)
>
> ```
>
>

 _Originally posted by @Coding-Meet in [#336](https://github.com/orchestr7/ktoml/issues/336#issuecomment-3301251980)_

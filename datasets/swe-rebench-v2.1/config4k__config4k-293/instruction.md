`kotlin.text.Regex` should be serializable
Inspired by a great work of @alexmihailov in https://github.com/Kotlin/kotlinx.serialization/pull/2137

### Additional contract requirements

Configuration serialization must support decoding and encoding `kotlin.text.Regex` values. A serialized Regex must retain its pattern and options so that decoding it preserves the original Regex semantics.

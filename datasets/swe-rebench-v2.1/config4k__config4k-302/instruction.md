`java.util.regex.Pattern` should be serializable

### Additional contract requirements

Pattern values must survive serialization and deserialization through the library without changing their pattern text or compilation flags.

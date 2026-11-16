Simplify `comments` configuration
The `comments` configuration is currently an object with 5 customisations expressed as Bool and 1 main `isEnabled` flag.

In my head, we could express this the same way with an enum/option set of values and a single `commentFeatures` array/set.. Something like the following:

**Disable Comments:**
```yaml
commentFeatures: []
```

**Everything:**
```yaml
commentFeatures:
- title
- description
- example
- externalDocumentation
- capitalized
```

**Description (capitalized):**
```yaml
commentFeatures:
- description
- capitalized
```

In Swift, this would be something like the following:

[HIDDEN]

Alternatively I'll just deswiftify the boolean properties on the existing object.

### Additional contract requirements

- The configuration key is `commentOptions`; setting it to an empty array disables comment generation.
- The available feature values are `title`, `description`, `example`, `externalDocumentation`, and `capitalized`. For a non-empty selection, only selected features are generated. This includes `externalDocumentation`, which controls whether external-documentation comments are generated when documentation is available. The default is all five features.

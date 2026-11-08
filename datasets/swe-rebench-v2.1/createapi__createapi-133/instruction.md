Change `rename.properties` to use schema names
I observe in [this comment](https://github.com/CreateAPI/CreateAPI/pull/106#discussion_r938926493) that `rename.properties` requires the format of the post-processed entity name that will be attached to the final entity.

## Example

The following config:
```yaml
Pet:
  properties:
    example_name:
      type: string
    enabled:
      type: boolean
    source_url:
      type: String
```

will result in the entity:
```swift
struct Pet {
    var exampleName: String
    var isEnabled: String // due to useSwiftyPropertyNames
    var sourceURL: String // due to isReplacingCommonAcronyms
}
```

When a developer uses `rename.properties`, they are required to use the final processed entity name for the key and the value is a literal translation [1], no processing is done on the renamed property. Additionally, the developer has to know what acronyms are used and the states of the `pluralizeProperties`, and `useSwiftyPropertyNames`. This can cause a lot of problems during renaming and I omit examples of mixture of these properties because it's pretty straightforward.

```yaml
rename:
  properties:
    Pet.isEnabled: somethingElse
    Pet.sourceURL: another_url # will literally become `another_url` on the entity
```

## Change
To be consistent with `include/exclude` and to be more clear with how the config should be created, we should instead change `rename.properties` to use the schema object names for keys and values.

```yaml
rename:
  properties:
    Pet.enabled: something_else
    Pet.source_url: another_url
```

would result in the entity:
```swift
struct Pet {
    var exampleName: String
    var somethingElse: String
    var anotherURL: String
}
```

---

- [1] I don't think that literal translations should be an intended use of `rename.properties`. If a developer really _really_ wanted to break their own convention we could implement some kind of literal renaming option that ignores the naming processing steps. I think a comment would be very clear and declarative, but I don't know how the YAML would parse that at the moment:

```yaml
rename:
  properties:
    Pet.enabled: something_else
    Pet.source_url: another_url # literal
```

### Additional contract requirements

For the `Pet.enabled` rename example, when `useSwiftyPropertyNames` is disabled, renaming the schema property to `something_else` produces the Swift property `somethingElse` without an `is` prefix. When that naming option is enabled, its boolean naming behavior continues to apply to the renamed property.

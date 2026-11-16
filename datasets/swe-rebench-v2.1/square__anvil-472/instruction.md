Allow replacing `@ContributesSubcomponent`
I didn't implement this feature, because it seemed unnecessary. But there's actually at least one reasonable use case: contributing a new subcomponent with different scope annotations, e.g.
```kotlin
@ContributesSubcompnent(scope = Unit::class, parentScope = Any::class)
interface Subcomponent

@ContributesSubcompnent(scope = Unit::class, parentScope = Any::class, replaces = [Subcomponent::class])
@Singleton
interface OtherSubcomponent
```

### Additional contract requirements

- A contributed subcomponent may name another contributed subcomponent as a replacement. The replaced subcomponent is not generated in place of the replacement.
- A replacement may carry a distinct scope annotation such as `@Singleton`; it remains usable, and its scope annotation is present on the generated subcomponent.
- The generated replacement uses its own contribution exclusions rather than inheriting the replaced subcomponent's exclusions.

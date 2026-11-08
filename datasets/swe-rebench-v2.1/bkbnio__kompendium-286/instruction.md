Nullability is broken by move to reference schemas
**Describe the bug**
The switch to reference schemas completely broken Kompendiums ability to handle null fields.  Since each type gets stored only once, but nullability is stored on the object schema level, this leads to a situation where defining one field of Type A that _is_ nullable and another field of type A that _is not_ nullable cannot be handled.

**To Reproduce**
```kotlin
data class Something(val a: String, val b: Int)

data class ManyThings(
  val someA: Something,
  val someB: Something?
)
```

This will not display the nullability correctly in Kompendium

**Expected behavior**
It should display properly

### Additional contract requirements

- For this fixture, represent `ManyThings.someB` with `oneOf` containing `{"type":"null"}` followed by `{"$ref":"#/components/schemas/Something"}`, while `someA` remains a direct reference to `Something`.

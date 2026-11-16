ArrayAccess limitations
@swaner mentioned an issue with the `ArrayAccess` casting found in the `ArrayCaster` class in #206. I have a fix for that specific issue, but in implementing it I have discovered some oversights in my original implementation of the `ArrayAccess` caster which causes it to not work for very basic `ArrayAccess` implementations that do not also implement `IteratorAggregate`.

[HIDDEN] I don't think this would really be a breaking change, as it would simply add in a check for a scenario we couldn't cover. As a bonus, we would also gain support for `ArrayObject` implementations in that caster.

@brendt - Any thoughts here? Happy to create a PR if this sounds like the right course.

### Additional contract requirements

ArrayAccess destinations that cannot be traversed must be rejected rather than silently mishandled. Traversable ArrayAccess destinations, including ArrayObject, must be supported for casting.

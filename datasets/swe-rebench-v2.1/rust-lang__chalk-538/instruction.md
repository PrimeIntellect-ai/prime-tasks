Coherence issue with overlapping imps with assoc types
Given
```
trait Iterator {
    type Item;
}

trait Trait {}

impl<T> Trait for T where T: Iterator<Item = u32> {}
impl<T> Trait for T where T: Iterator<Item = u32> {}

struct Foo {}
```
we don't throw a coherence error. Adding `impl Iterator for Foo { type Item = u32; }` makes it appear, but it should work without it too.

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->

<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"Mcat12"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->

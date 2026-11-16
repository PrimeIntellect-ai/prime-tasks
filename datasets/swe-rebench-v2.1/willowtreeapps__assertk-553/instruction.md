Relax bounds of built-in value-asserting functions.
I'm migrating a couple thousand test cases from Truth, and another thing that is coming up similar to https://github.com/willowtreeapps/assertk/issues/393#issuecomment-2428206350 is that calls to `isTrue()` need to become `isNotNull().isTrue()` on nullable subjects. In general this makes sense! However, the fact that I can call `.isEqualTo(true)` _without_ the `isNotNull()` check just feels bad. It's shorter! Why wouldn't I _always_ then do that?

I fully understand and am justifying calls to `isNotNull()` before things like `startsWith()` which operate on the actual value and therefore need to null-check it first. But `isTrue()` and `isFalse()` seem like they should be equivalent to `isEqualTo(true)` and `isEqualTo(false)`, just maybe with a better message. That makes me think they should operate on `Boolean?` and not just `Boolean`.

### Additional contract requirements

- `isTrue` and `isFalse` are assertions on a nullable `Boolean` subject, i.e. they accept a subject of type `Boolean?`.
- `isTrue` passes when the subject is `true`. When the subject is `false` it fails with the message `expected:<[tru]e> but was:<[fals]e>`, and when the subject is `null` it fails with the message `expected:<true> but was:<null>`.
- `isFalse` passes when the subject is `false`. When the subject is `true` it fails with the message `expected:<[fals]e> but was:<[tru]e>`, and when the subject is `null` it fails with the message `expected:<false> but was:<null>`.

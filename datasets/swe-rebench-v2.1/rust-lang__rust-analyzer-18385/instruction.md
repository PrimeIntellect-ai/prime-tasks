Assist to derive `type alias = signature` for a function
Given some function
```rs
unsafe fn foo(param: u32) -> String { ... }
```
with the cursor on `foo` we should offer an assist that generates a type alias for the function's signature
```
type FooFn = unsafe fn(u32) -> String;
```

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->

<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"Giga-Bowser"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->

### Additional contract requirements

- The generated alias name is inserted as an editor snippet placeholder. The inserted text is `type ${0:FooFn} = ...;`, where `${0:FooFn}` marks the alias name `FooFn` as a snippet placeholder (tab stop 0) so the user can rename it. Both the named-parameter and unnamed-parameter styles use this placeholder.

Cases like `void method(boolean arg1, org.package.ClassA arg2)` are not covered by `RelocatorRemapper`
> The relocation of method signatures in `@Metadata` annotation fails if there is a primitive argument before a relocating class, such as `void method(boolean a, SomeClass b)` whose descriptor is `(ZLorg/package/SomeClass;)V` which fails the regex [`([\\[()]*)?L([^;]+);?`](https://github.com/GradleUp/shadow/blob/b873c701c1d96c14d5e6f57192c7de18888b9b48/src/main/kotlin/com/github/jengelman/gradle/plugins/shadow/internal/RelocatorRemapper.kt#L68).
>
> [HIDDEN]
>

 _Originally posted by @phinner in https://github.com/xpdustry/kotlin-shadow-relocator/issues/30#issuecomment-3275090750_

### Additional contract requirements

- Relocation must work for method signatures where a primitive argument precedes a class type that is relocated, while preserving the surrounding descriptor.

Setting `#[Strict]` on parent is not applied on children
```php
#[Strict]
abstract class DtoBase {}

final class Dto extends DtoBase {}
```

then `Dto` is not strict because `[HIDDEN]` reads attributes [HIDDEN].

Is it intended or a bug? Thanks!

### Additional contract requirements

- A class is strict when constructing it with properties that are not declared on it throws `Spatie\DataTransferObject\Exceptions\UnknownProperties`.
- `#[Strict]` is inherited through the whole parent chain: a child or grandchild of a class annotated with `#[Strict]` is strict even when it does not carry the attribute itself.

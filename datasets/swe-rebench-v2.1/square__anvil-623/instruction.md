boundType does not appear to support Any
This piece of code:

```
@ContributesMultibinding(ActivityInjection::class, boundType = Any::class)
class TestViewModel @Inject constructor() : SimpleStackViewModel() {
...
}
```

Will throw an error:

```TestViewModel contributes a binding for kotlin.Any, but doesn't extend this type.```

Obviously, this class DOES extend Any.

This worked in Anvil 2.3.4 but it's now broken in 2.4.1.

Setting bound type to the `SimpleStackViewModel` works, so it appears just using `Any` as a boundType is an issue.

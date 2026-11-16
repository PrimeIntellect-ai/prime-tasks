Ability to use constant array as `IsIn` and `IsNotIn` argument
Constant array can not be passed as `IsIn` argument, which is a common thing to validate against a constant array not a dynamic list. Example:

```
const Currencies = ['ETH', 'BTC'] as const;

class Payment {
  @IsIn(Currencies)
  currency: string
}
```

Generates compilation error:

```
Argument of type 'readonly ["ETH", "BTC"]' is not assignable to parameter of type 'any[]'. The type 'readonly ["ETH", "BTC"]' is 'readonly' and cannot be assigned to the mutable type 'any[]'
```

https://www.typescriptlang.org/docs/handbook/release-notes/typescript-3-4.html#const-assertions
[HIDDEN]

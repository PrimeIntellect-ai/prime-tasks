"no-global-import" should not apply to named global imports
Solhint correctly throws a warning for the following code:

```solidity
import "../../src/Helpers.sol";
```

But it incorrectly continues to throw a warning even when naming the global import, like this:

```solidity
import "../../src/Helpers.sol" as H;
```

Using global imports in this way should be completely acceptable since the global namespace is not polluted.

The use case, in my case, is a [`Helpers.sol`](https://github.com/PaulRBerg/prb-test/blob/48482b1be0ca1e3ad6c0f7dd568d13f79fbd4dba/src/Helpers.sol) file with lots of overloaded functions that cannot be imported individually (e.g. the `eq` functions). Another place where I use this technique is in [PRBMath](https://github.com/PaulRBerg/prb-math/blob/ea0ad4fcbc286d1dec490f07b93f3304ff94dda2/src/ud60x18/ValueType.sol#L4-L6).

`payable` decorator in interface functions not enforced by `implements`
### Version Information

* vyper Version (output of `vyper --version`): `0.3.11+commit.819de669`
* OS: `linux`
* Python Version (output of `python --version`): `3.11.3`

### What's your issue about?

If an interface function (in a `.vyi` file) is marked as `payable`, it is not enforced via `implements` keyword.

#### Example

```vy
# TestI.vyi
@external
@payable
def foo() -> uint256:
    ...
```

```vy
# Test.vy
import TestI as testI
implements: testI

@external
def foo() -> uint256:
    return 0
```

```console
vyper Test.vy
```

```console
0x61002661000f6000396100266000f35f3560e01c63c2985578811861001e5734610022575f60405260206040f35b5f5ffd5b5f80fd8418268000a16576797065728300030b001
```

This should not compile actually.

### How can it be fixed?

Enforce `payable` decorator via `implements` keyword.

_abi_encode with empty string
### Version Information

* vyper Version (output of `vyper --version`): 0.3.2
* OS: linux
* Python Version (output of `python --version`): 3.10.2

### What's your issue about?

```
@external
def f1() -> Bytes[100]:
    return _abi_encode("")
```

Expected: `0x20, 0x40, 0x20, 0`
Found: `0, 0x40, 0x20, 0`

It is another Solidity test and the similar `_abi_encode` problem.
The first value (I guess it is the offset) is always 0x20 if the string is not empty.

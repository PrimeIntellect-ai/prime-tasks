AttributeError: 'str' object has no attribute 'compare_type'
### Version Information

* vyper Version (output of `vyper --version`): 0.3.3
* OS: macOS
* Python Version (output of `python --version`): 2.7.16

### What's your issue about?
```
vyper-0.3.3 error: AttributeError: 'str' object has no attribute 'compare_type'
[14131] Failed to execute script 'vyper_compile' due to unhandled exception!
```
```
event E:
    _: DynArray[DynArray[uint256, 5], 5]

@external
def createEvent(x: uint256):
    arr: DynArray[DynArray[uint256, 5], 5] = [[], []]
    arr[0] = [0, 0]
    arr[1] = [0, 0]
    arr[0][0] = x
    arr[0][1] = x + 1
    arr[1][0] = x + 2
    arr[1][1] = x + 3
    log E(arr)

```

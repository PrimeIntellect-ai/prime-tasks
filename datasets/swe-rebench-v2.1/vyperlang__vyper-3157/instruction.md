`blockhash()` allowed in `pure` functions
### Version Information

* vyper Version (output of `vyper --version`): 0.3.7+commit.6020b8bb
* OS: OSX
* Python Version (output of `python --version`): 3.8.0

### What's your issue about?

The usage of the built-in function `blockhash()` is currently allowed in `pure` functions although it is reading the blockchain state.
For example, the following contract compiles successfully:
```Vyper
@external
@pure
def foo(x: uint256)-> bytes32:
    return blockhash(x)
```
### How can it be fixed?

Functions that make use of the `blockhash()` built-in must be declared as `view`, `nonpayable` or `payable`.

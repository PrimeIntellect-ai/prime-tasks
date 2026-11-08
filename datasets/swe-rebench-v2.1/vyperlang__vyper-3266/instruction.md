`FunctionDef` inside interfaces can be decorated
### Version Information

* vyper Version (output of `vyper --version`): 0.3.8+commit.02339dfd
* OS: OSX
* Python Version (output of `python --version`): 3.8.0

### What's your issue about?

`FunctionDef` inside interfaces can be decorated. For example, the following contract compiles.

```Vyper
interface A:
    @external
    @nonreentrant("key")
    @pure
    def foo(): nonpayable
```

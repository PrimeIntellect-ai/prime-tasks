compiler panic when type checking struct iterator
### Version Information

* vyper Version (output of `vyper --version`): 0.4.1

### What's your issue about?

the following code raises a panic instead of a proper typechecker exception:
```vyper
struct Tx1:
    x: uint256
    y: address

struct Tx2:
    x: uint256
    y: address

@external
def test():
    txs: Tx1[20] = empty(Tx1[20])

    for txx: Tx2 in txs:  # should be `txx: Tx1`
        pass
```
raises:
```
During handling of the above exception, another exception occurred:

vyper.exceptions.CodegenPanic: unhandled exception , parse_For

  contract "tmp/bar.vy:14", function "test", line 14:4
       13
  ---> 14     for txx: Tx2 in txs:  # should be `txx: Tx1`
  ------------^
       15         pass


This is an unhandled internal compiler error. Please create an issue on Github to notify the developers!
https://github.com/vyperlang/vyper/issues/new?template=bug.md
```

### How can it be fixed?

Fill this in if you know how to fix it.

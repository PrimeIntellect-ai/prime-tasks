Dynamic array of `HashMap`s allowed but unusable
### Version Information

* vyper Version (output of `vyper --version`): 0.3.8+commit.6020b8bb
* OS: OSX
* Python Version (output of `python --version`): 3.8.0

### What's your issue about?

While it is possible to declare a storage variable of type `DynArray[HashMap[A,B],n]` where `A` and `B` are valid types for the keys and values of `HashMap` and `n` is a positive integer, it seems impossible to compile a contract that update, append or read elements of such array. Moreover, having it as `public` will lead the compiler to fail as it cannot create a getter that takes a `HashMap` as argument.

The following contract will compile:
``` Vyper
foo: DynArray[HashMap[uint8,uint8], 2]
```
While the compiler will output `vyper.exceptions.InvalidType: Maps are not supported for function arguments or outputs` when trying to compile one of the following contracts
``` Vyper
foo: public(DynArray[HashMap[uint8,uint8], 2])
```
``` Vyper
foo: DynArray[HashMap[uint8,uint8], 2]
@external
def test() -> uint8:
    return self.foo[0][0]
```
### How can it be fixed?

Similarly to its behaviour for static arrays of `HashMap` or `Struct` with a field of type `HashMap`, the compiler should probably output an exception when defining a variable of type Dynamic array of `HashMap`

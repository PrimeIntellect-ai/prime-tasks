can't declare variable `public` but can define custom getter
### Version Information

* vyper Version:  0.3.4+commit.f31f0ec
* OS: osx
* Python Version: 3.8.9

### What's your issue about?

This code fails to compile:

```
slates : public(HashMap[bytes32, DynArray[address, 15]])
```

but I can define my own getter for that type just fine:

```
slates : HashMap[bytes32, DynArray[address, 15]]

@external
def slate(sid :bytes32) -> DynArray[address, 15]:
   return self.slates[sid]
```

### Additional contract requirements

- A contract variable declared `slates: public(HashMap[bytes32, DynArray[address, 15]])` must compile and expose an auto-generated getter `slates(key: bytes32, i: uint256) -> address` that returns the address stored at index `i` of the dynamic array stored under `key`.
- A contract variable declared `my_list: public(DynArray[uint256, 5])` must expose an auto-generated getter `my_list(i: uint256) -> uint256` that returns the value stored at index `i`.
- A contract variable declared `my_list: public(DynArray[DynArray[uint256, 5], 5])` must expose an auto-generated getter `my_list(i: uint256, j: uint256) -> uint256` that returns the value stored at outer index `i` and inner index `j`.

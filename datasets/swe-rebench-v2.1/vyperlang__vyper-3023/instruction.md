Source map contains an extra instruction
### Version Information

* vyper Version (output of `vyper --version`): 0.3.4+commit.f31f0ec
* OS: Linux Mint
* Python Version (output of `python --version`): Python 3.8.10

### What's your issue about?

It looks to me like source maps in this version extend one instruction beyond where they're supposed to.

Let's take as an example the following extremely simple contract:

```vyper
@external
@payable
def __init__():
    pass

@external
@payable
def __default__():
    pass
```

It compiles to the following (deployed) bytecode: (we'll ignore the constructor bytecode, due to #1998 still being an outstanding issue)

```
0x6003361161000c57610014565b60003560e01c505b00a165767970657283000304
```

Now, the last eleven bytes of this are metadata, but if we remove those we get the following decompilation:

```
0x00: PUSH1 0x03
0x02: CALLDATASIZE
0x03: GT
0x04: PUSH2 0x000c
0x07: JUMPI
0x08: PUSH2 0x0014
0x0b: JUMP
0x0c: JUMPDEST
0x0d: PUSH1 0x00
0x0f: CALLDATALOAD
0x10: PUSH1 0xe0
0x12: SHR
0x13: POP
0x14: JUMPDEST
0x15: STOP
```

Which has 15 instructions.

Meanwhile, the source map is as follows:

```
-1:-1:4:-;;;;:::-;;:::-;:::-;;;;;;:::-;;
```

This source map contains 15 semicolons -- which is to say, *16* instructions.  That's one more instruction than actually exists; the source map extends into the metadata area.  A disassembler that looked at the source map to know where to stop would report a `LOG1` just beyond the final `STOP`, when in fact that `0xa1` isn't intended as a `LOG1` at all.

feat request: new func __RIGHTPAD()
The problem:
When we want to store a bytes as a constant we have 2 choices.

1) Create a constant without any padding (i.e. 0xBEEF) and it gets treated as a value so its left padded.  Then when we use it we can some bitshifting or some MSTORE's with offset to get the important bytes to move the high order bits.  This is a waste of runtime gas.
2) Create a constant as fully right padded (i.e. 0xBEEF000000000000000000000000000000000000000000000000000000000000)  This way saves gas but it's kind of annoying to have this huge long number in the code.

Solution:

A new function __RIGHTPAD(0xBEEF), when compiled will be the same as the right padded value in #2 above.  This way the code is more readable, and we don't have to use any runtime gas to bitshift.

We could also consider something more flexible than just right padding.  Like __PAD(0xBEEF, left 0's, right 0's) but this sounds unnecessarily complex.  Left padding is done by default, so we don't need a func for that.  And mid padding is easily achieved by adding in the zeros yourself on either side.

### Additional contract requirements

- `__RIGHTPAD` accepts exactly one argument.
- Compiling a `__RIGHTPAD` call emits a `PUSH32` opcode followed by the supplied literal right-padded with zero bytes to a full 32-byte word.
- Calls to `__RIGHTPAD` with any number of arguments other than one must be rejected.

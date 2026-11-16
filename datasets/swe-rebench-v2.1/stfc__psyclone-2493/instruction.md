NemoOuterArrayRange2LoopTrans bug when array-index expression includes array reference
Processing a reference of the form `this(jp)%that(:, map(ij) - np, :)` causes the apply method of `NemoOuterArrayRange2LoopTrans` to fail. The culprit is:

     [HIDDEN]

[HIDDEN] (i.e. allowing for an access to a member of a derived type). However, that `walk` ends up giving us `map(ij)` in this case which is wrong.

### Additional contract requirements

- When applying `NemoOuterArrayRange2LoopTrans` to a reference whose range-index expression contains an array reference, the transformation must succeed and operate on the intended outer array range, not the nested array reference.

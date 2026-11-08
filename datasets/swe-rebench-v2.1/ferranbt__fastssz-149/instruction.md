`ssz.ExtendUint32` and `hh.AppendUint32` undefined error in the generated code
Hi,

I have the following struct and use `sszgen` to generate ssz code for it:
```
type Container struct {
	List []uint32 `ssz-max:"100"`
}
```
However, the generated code has two errors:
- In `UnmarshalSSZ`: `undefined: ssz.ExtendUint32`
- In `HashTreeRootWith`: `hh.AppendUint32 undefined (type ssz.HashWalker has no field or method AppendUint32)`

Why does `fastssz` not support uint32 list?

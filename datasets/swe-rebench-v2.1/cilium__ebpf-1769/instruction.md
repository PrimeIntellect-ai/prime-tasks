bpf2go: emit `structs.HostLayout` into generated structs
We recently made a change to make sure our syscall wrappers continue to work on future versions of go, see #1681. Timo points out that we should do the same for bpf2go:

              Looks good, thanks! We should probably also emit these in bpf2go types.

_Originally posted by @ti-mo in https://github.com/cilium/ebpf/pull/1681#pullrequestreview-2620432502_

[HIDDEN]

### Additional contract requirements

- Every struct emitted by GoFormatter, including nested structs and datasec declarations, must start with `_ structs.HostLayout;`.
- Generated bpf2go Go source using this field must import the `structs` package so the declarations compile.

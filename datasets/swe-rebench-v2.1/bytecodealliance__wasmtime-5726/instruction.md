Cranelift: "register allocation: SSA(VReg(vreg = 145, class = Int), Inst(0))" in upcoming 0.93 when compiling with optimizations
### `.clif` Test Case

```
test compile
set opt_level=speed_and_size
target aarch64

function u0:33() system_v {
    ss0 = explicit_slot 32
    sig0 = (i64, i64, i64, i64, i64) -> i64, i64 system_v
    fn0 = colocated u0:0 sig0
    jt0 = jump_table [block36, block38]

block0:
    v80 = iconst.i32 0
    v91 = iconst.i64 0
    v92 = iconst.i64 0
    v96 = iconst.i64 0
    v235 = iconst.i64 0
    v236 = iconst.i64 0
    v237 = iconst.i64 0
    v238, v239 = call fn0(v236, v237, v91, v92, v235)  ; v236 = 0, v237 = 0, v91 = 0, v92 = 0, v235 = 0
    v97 = iadd v238, v96  ; v96 = 0
    br_table v80, block37, jt0  ; v80 = 0

block36:
    trap user0

block37:
    trap unreachable

block38:
    v98 = load.i8 notrap v97
    v99 = fcvt_from_uint.f64 v98
    stack_store v99, ss0
    trap user0
}
```

### Steps to Reproduce

* `clif-util test repro.clif`

### Expected Results

Compiles

### Actual Results

Regalloc checker error: `register allocation: SSA(VReg(vreg = 145, class = Int), Inst(0))`

### Versions and Environment

Cranelift version or commit: Cranelift 0.93 (43022c862a1d497f4b8c7c2fce47148775503add on the release-6.0.0 branch) which is not yet released.

Operating system: Linux

Architecture: AArch64

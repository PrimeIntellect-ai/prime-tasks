Exists-forall gives false solution for consts
Solving
```
exists<const C> {
    forall<const D> {
        C = D
    }
}
```
gives `Unique; substitution [?0 := !1_0], lifetime constraints []` instead of the expected `No possible solution`.

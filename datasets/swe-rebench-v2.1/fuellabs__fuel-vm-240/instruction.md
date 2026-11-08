Logarithm instruction `mlog` needs discussion
I would expect that `assert(1000.logarithm(10) == 3);` would pass, but it does not.
Instead, logging `1000.logarithm(10)` returns `2`,

The testing I've done uses this implementation in sway:
```
impl Logarithm for u64 {
    fn logarithm(self, base: Self) -> Self {
        asm(r1: self, r2: base, r3) {
            mlog r3 r1 r2;
            r3: Self
        }
    }
}
```
Note that other cases are working as expected, i.e:
```
assert(4.logarithm(2) == 2);
assert(16.logarithm(2) == 4);
assert(9.logarithm(3) == 2);
assert(100.logarithm(10) == 2);
```

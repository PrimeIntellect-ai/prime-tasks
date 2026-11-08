`usize` not usable as literal key
```
error: unsupported key expression
     --> src\movements.rs:32592:5
      |
32592 |     14usize /* SpotId::Amagi_Breach__East_Entrance__East */ => &TIMES_WATER__AMAGI_BREACH__EAST_ENTRANCE__EAST,
      |     ^^^^^^^
```

#262 supposedly enabled usize for PhfHash, but it's not present in https://github.com/rust-phf/rust-phf/blob/master/phf_macros/src/lib.rs where I would assume it should be to allow use in `phf_map!`.

### Additional contract requirements

`isize` should also be usable as a literal key in `phf_map!`, in addition to `usize`.

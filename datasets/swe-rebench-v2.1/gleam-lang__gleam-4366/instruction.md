Code action for "Inline variable" not always working on record update arguments
The following snippet offers "Inline variable" 3 times in the code actions list

```gleam
type Couple {
  Couple(l: Int, r: Int)
}

pub fn main() {
  let c1 = Couple(l: 1, r: 1)
  let c2 = Couple(..c1, r: 1)
                    ^
}
```

The first option is correct.

Some of the options (the second and third in my case) offer this replacement
```gleam
pub fn main() {
  let c1 = Couple(lCouple(..c1, r: 1)1, r: 1)
}
```

or this if the selection is this
```gleam
  let c2 = Couple(..c1, r: 1)
                     ^
```

the replacement is
```gleam
  let c1 = Couple(l:Couple(..c1, r: 1), r: 1)
```

### Additional contract requirements

When the "Inline variable" code action is invoked on the variable used as the
record-update base (the `..c1` argument), it must replace that variable with its
definition and produce valid code. For the example above, inlining `c1` must
produce:

```gleam
pub fn main() {
  let c2 = Couple(..Couple(l: 1, r: 1), r: 1)
}
```

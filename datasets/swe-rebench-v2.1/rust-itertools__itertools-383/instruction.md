Combination on zero-sized array
Combination(0) seems to return an empty array.
However, the result differs when the original list is empty or not.

I think it would be better to produce [] instead of None.

https://play.rust-lang.org/?version=stable&mode=debug&edition=2018&gist=dad32c5aeae27dcd9b14ce8475b5fa79

```{.rs}
use itertools::*; // 0.8.0
fn main() {
    let a: Vec<usize> = vec![1usize];
    let b: Vec<usize> = vec![];
    println!("{:?}", a.iter().combinations(0).next()); // Some([])
    println!("{:?}", b.iter().combinations(0).next()); // None
}
```

https://www.wolframalpha.com/input/?i=0+choose+0
https://www.wolframalpha.com/input/?i=1+choose+0

### Additional contract requirements

- For `.combinations_with_replacement(0)`, both empty and non-empty inputs yield exactly one empty combination (`vec![vec![]]`).

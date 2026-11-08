RegexSet and Regex give different results for the same pattern in 1.9
#### What version of regex are you using?

`1.9.3`. The issue is present in regex `1.9.0` and later.

#### Describe the bug at a high level.

`RegexSet::new([r"(?m)^ *v [0-9]"]).unwrap().is_match("v 0")` incorrectly returns false in version 1.9.0 and later.

It returns true in 1.8.4.

It returns true if I use a `Regex` instead of a `RegexSet`.

#### What are the steps to reproduce the behavior?

```rust
fn main() {
    let pattern = r"(?m)^ *v [0-9]";
    let text = "v 0";

    let re = regex::Regex::new(pattern).unwrap();
    println!("re is: {re:?}");
    println!("{}", re.is_match(text)); // true (correct)

    let rs = regex::RegexSet::new([pattern]).unwrap();
    println!("rs is: {rs:?}");
    println!("{}", rs.is_match(text)); // false (incorrect)
}
```

([playground link](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=eb964fd144925df0b5fd15e0d1d61279))

#### What is the actual behavior?

```
re is: Regex("(?m)^ *v [0-9]")
true
rs is: RegexSet(["(?m)^ *v [0-9]"])
false
```

#### What is the expected behavior?

The last line should be `true`.

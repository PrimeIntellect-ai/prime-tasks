Regex matching changed in 1.8.0
#### What version of regex are you using?

This appears to be a bug in 1.8.0.

#### Describe the bug at a high level.

Something in the regex matching changed in 1.8.0. I suspect it might be a bug in the handling of word boundaries, `\b`.

#### What are the steps to reproduce the behavior?

```rust
use regex::Regex;

fn main() {
    let re = Regex::new(r#"(?i:(?:\b|_)win(?:32|64|dows)?(?:\b|_))"#).unwrap();
    for s in ["ubi-Darwin-x86_64.tar.gz", "ubi-Windows-x86_64.zip"] {
        println!("{s} =~ /{}/ => {}", re, re.is_match(s));
    }
}
```

With `regex` 1.8.0 the given regex will match both strings, which is surprising. The "win" in "Darwin" is not preceded by a word boundary or underscore. In 1.7.3, this matches only the second string, as I'd expect.

#### What is the actual behavior?

With 1.8.0:

```
$> cargo run
    Finished dev [unoptimized + debuginfo] target(s) in 0.00s
     Running `target/debug/regex-issue`
ubi-Darwin-x86_64.tar.gz =~ /(?i:(?:\b|_)win(?:32|64|dows)?(?:\b|_))/ => true
ubi-Windows-x86_64.zip =~ /(?i:(?:\b|_)win(?:32|64|dows)?(?:\b|_))/ => true
```

With 1.7.3:

```
$> cargo run
    Finished dev [unoptimized + debuginfo] target(s) in 0.00s
     Running `target/debug/regex-issue`
ubi-Darwin-x86_64.tar.gz =~ /(?i:(?:\b|_)win(?:32|64|dows)?(?:\b|_))/ => false
ubi-Windows-x86_64.zip =~ /(?i:(?:\b|_)win(?:32|64|dows)?(?:\b|_))/ => true
```

#### What is the expected behavior?

I expect this to work the way it does in 1.7.3.

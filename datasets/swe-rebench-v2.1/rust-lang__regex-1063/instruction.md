reverse inner literal optimization results in incorrect match offsets in some cases
#### What version of regex are you using?

The bug is present in version 1.9.0 and 1.9.1.
1.8.4 was the last working version.

#### Describe the bug at a high level.

I am using the regex crate for parsing textual video durations and getting the duration in seconds.
After updating the regex crate to version 1.9.0, my regex fails to parse durations with more than 2 hour digits.

The + operator I use for matching an arbitrary amount of hour digits now only matches 1 or 2 digits.

#### What are the steps to reproduce the behavior?

Regex: `(?:(\d+)[:.])?(\d{1,2})[:.](\d{2})`

Here is my parsing function.

```rust
/// Parse textual video length (e.g. `0:49`, `2:02` or `1:48:18`)
/// and return the duration in seconds.
pub fn parse_video_length(text: &str) -> Option<u32> {
    static VIDEO_LENGTH_REGEX: Lazy<Regex> =
        Lazy::new(|| Regex::new(r#"(?:(\d+)[:.])?(\d{1,2})[:.](\d{2})"#).unwrap());
    VIDEO_LENGTH_REGEX.captures(text).map(|cap| {
        let hrs = cap
            .get(1)
            .and_then(|x| x.as_str().parse::<u32>().ok())
            .unwrap_or_default();
        let min = cap
            .get(2)
            .and_then(|x| x.as_str().parse::<u32>().ok())
            .unwrap_or_default();
        let sec = cap
            .get(3)
            .and_then(|x| x.as_str().parse::<u32>().ok())
            .unwrap_or_default();

        hrs * 3600 + min * 60 + sec
    })
}
```

#### What is the actual behavior?

The hour group only matches the number 2, so the parsed duration is `2:12:39` or 7959 seconds

```rust
parse_video_length("102:12:39") == Some(7959)
```

#### What is the expected behavior?

```rust
parse_video_length("102:12:39") == Some(367959)
```

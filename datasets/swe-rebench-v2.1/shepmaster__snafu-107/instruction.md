Use doc comments as default Display implementations
A lot of my errors look like this with snafu:
```rust
/// The Error type for splits files that couldn't be parsed by the FaceSplit
/// Parser.
#[derive(Debug, snafu::Snafu)]
pub enum ParseError {
    /// Expected the title, but didn't find it.
    #[snafu(display("Expected the title, but didn't find it."))]
    ExpectedTitle,
    /// Expected the goal, but didn't find it.
    #[snafu(display("Expected the goal, but didn't find it."))]
    ExpectedGoal,
    /// Expected the attempt count, but didn't find it.
    #[snafu(display("Expected the attempt count, but didn't find it."))]
    ExpectedAttemptCount,
    /// Expected the name of the segment, but didn't find it.
    #[snafu(display("Expected the name of the segment, but didn't find it."))]
    ExpectedSegmentName,
    /// Expected the split time, but didn't find it.
    #[snafu(display("Expected the split time, but didn't find it."))]
    ExpectedSplitTime,
    /// Expected the best segment time, but didn't find it.
    #[snafu(display("Expected the best segment time, but didn't find it."))]
    ExpectedBestSegmentTime,
}
```
As you can see all the display attributes are basically verbatim copied into the doc comments. It would be cool if Snafu used the doc comment as the display impl for a variant if there is no explicit snafu(display(...)) attribute.

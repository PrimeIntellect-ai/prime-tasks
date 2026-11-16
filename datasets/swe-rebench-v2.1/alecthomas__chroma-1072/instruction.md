Extraneous colors in Gleam type highlighting
### Is there an existing issue for this?

- [x] I have searched the existing issues

### Describe the bug

When highlighting Gleam code, the type names between parenthesis and in function returns have their first letter with a different font color an background. I would expect those names to either have the same color as the type declarations without parentheses, or to not be colored.

### To Reproduce

Example in [chroma playground](https://swapoff.org/chroma/playground/#eyJsYW5ndWFnZSI6IkdsZWFtIiwic3R5bGUiOiJtb25va2FpbGlnaHQiLCJ0ZXh0IjoicHViIHR5cGUgVGFibGUgPSBTdWJqZWN0KE1lc3NhZ2UpXG5cbnB1YiB0eXBlIE1lc3NhZ2Uge1xuICBSZWdpc3RlckZlZWQoU3RyaW5nLCBQb2xsZXIpXG59XG5cbnB1YiBmbiBzdGFydCgpIC0-IFRhYmxlIHtcbiAgdG9kb1xufVxuIiwiY2xhc3NlcyI6ZmFsc2V9)

To reproduce it in the command line:

    chroma -l gleam --html <source>

Where source is:
```gleam
pub type Table = Subject(Message)

pub type Message {
  RegisterFeed(String, Poller)
}

pub fn start() -> Table {
  todo
}
```

### Additional contract requirements

- When lexing Gleam, type names inside parentheses and in function return types must be emitted as `NameClass` tokens.

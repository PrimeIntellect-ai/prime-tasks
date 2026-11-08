Newline is missing in error output
I tried this:
```rust
#[derive(Clone, argh::FromArgs)]
#[argh(description = "...")]
struct Options {
    #[argh(option, description = "...")]
    bind_to: SocketAddr,
    #[argh(positional)]
    dir: PathBuf,
}
```

When I ran the program with no argument, it printed:
```
Required positional arguments not provided:
    dirRequired options not provided:
    --bind-to
```

The second line of the output was unreadable. I expected the output to be:
```
Required positional arguments not provided:
    dir
Required options not provided:
    --bind-to
```

[HIDDEN]

### Additional contract requirements

- When required positional arguments and required options are both missing, separate their diagnostic sections with a newline.

Formatting bug when using multi-line strings
Hi!
seems like I ran into a problem when using multi-line strings

**Describe the bug**

dprint-plugin-typescript version: 0.88

**Input Code**

```ts
describe(
    "Im testing dprint I should be hanging \
    I should be hanging",
    async () => {
        // test
    }
)
```

**Expected Output**

```ts
describe(
    "Im testing dprint I should be hanging \
    I should be hanging",
    async () => {
        // test
    },
);

```

**Actual Output**

```ts
describe(
"Im testing dprint I should be hanging \
    I should be hanging",
    async () => {
        // test
    },
);

```

Seems like the code inside `dprint/core` doesn't take into account all the possible ways of creating multi-line strings

```rust
[HIDDEN]
  let mut items = PrintItems::new();
  if add_ignore_indent {
    items.push_signal(Signal::StartIgnoringIndent);
  }
  items.extend(gen_string_lines(text, gen_line));
  if add_ignore_indent {
    items.push_signal(Signal::FinishIgnoringIndent);
  }
  items
}
```

I've tried to tackle this myself but I've no idea which other crates besides `dprint-plugin-typescript` are using `dprint/core` and what would be the consequences of changing such a basic function :\

### Additional contract requirements

- When formatting the reported call, preserve the leading indentation of the backslash-continued string and format the surrounding call with a trailing comma after the callback.

Add option to wrap when `MaxWidth` is configured
It would be really nice to be able to wrap wide columns onto newlines, rather than truncating them. Something like:

```
    let expected = concat!(
        "| id | destribution |    link    |\n",
        "|----+--------------+------------|\n",
        "| 0  |    Fedora    | https://ge |\n",
        "|    |              | tfedora.or |\n",
        "|    |              |     g/     |\n",
        "| 2  |   OpenSUSE   | https://ww |\n",
        "|    |              | w.opensuse |\n",
        "|    |              |   .org/    |\n",
        "| 3  |  Endeavouro  | https://en |\n",
        "|    |      s       | deavouros. |\n",
        "|    |              |    com/    |\n",
    );
```

when the max width is set to 10.

---

I had a go at this, and have the above test passing, but it required changing the public API of `MaxWidth` and didn't work great with type inference. Happy to push it up so you can take a look though.

### Additional contract requirements

When wrapping is selected, cell content wider than the configured maximum continues on additional lines rather than being truncated, preserving the full content. Wrapping can be selected by configuring `MaxWidth::wrapping(width)`. Content no wider than the configured maximum remains unchanged.

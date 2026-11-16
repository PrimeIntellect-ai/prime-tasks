Trimming trailing whitespace in borderless tables
I am using comfy-table to build tables without borders. It all works great until I start to unnittest my tables. In my unit tests I am comparing the tables' String representations, with the expected result stored in a file (which I read with `include_str!`). Because my editor is configured to trim trailing whitespace on save, the expected result file does not have them, but the generated table does. So in order to do the comparison I first need to trim all trailing whitespace from the generated table, which I find a little cumbersome and annoying.

[This](https://github.com/Nukesor/comfy-table/blob/33739f9d7fe238c116801d86ffbaafe18b76dde4/tests/presets_test.rs#L20) test illustrate what I mean. In my opinion all whitespace between `3` and `\n` should be gone.

Now, I do realize that this is a "problem" of my editor, and others would likely never encounter it. However I would still like to suggest trimming trailing whitespace from borderless tables, just because trailing whitespace is usually useless.

I would be more than happy to make a PR, but wanted to first double-check if such a change would be OK.

### Additional contract requirements

`Table::trim_fmt(&self) -> String` returns the table's formatted output with trailing whitespace removed from each line. Apart from that trimming, it preserves the formatted table content. This applies to table styles generally and is especially useful for borderless tables.

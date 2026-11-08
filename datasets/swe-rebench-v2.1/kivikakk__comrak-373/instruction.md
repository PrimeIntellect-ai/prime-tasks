Rendering of hard line breaks
`cmark-gfm` renders hard line breaks as two spaces followed by a newline. Since #214, `comrak` renders hard line breaks as a backslash followed by a newline. This change makes it a bit tricky to build up `comrak` ASTs programmatically, because if you put a hard line break at the end of a block it will get rendered as a backslash in the markdown. And then because commonmark specifies that a backslash at the end of a block is treated as a literal backslash instead of a line break, you will get a backslash in the output.

I tried to make a PR to change this behavior, but every option has some problems. Here are some possibilities:

1. Keep the current behavior, and require anyone constructing their own AST to be careful about inserting line breaks. This is doable, but tricky to do correctly. (For anyone running into a similar issue, our [workaround](https://github.com/tweag/nickel/pull/1880) was to use paragraph nodes instead of line breaks.)
2. Revert to the `cmark-gfm` behavior. This has the advantage of sticking close to upstream, but the disadvantage that hard line breaks at the beginning of a block no longer round-trip. This lack of a round-trip is how cmark-gfm currently behaves:
    ```
    $ echo '> \\n> a' | cmark-gfm -t commonmark test2.md | hexdump -C
    00000000  3e 20 20 20 0a 3e 20 61  0a                       |>   .> a.|
    $ echo '> \\n> a' | cmark-gfm -t commonmark test2.md | cmark-gfm -t commonmark | hexdump -C
    00000000  3e 20 61 0a                                       |> a.|
    ```
3. Make `NodeValue::LineBreak` have two variants (space-space or backslash). Downstream users get to choose which one they want. The parser remembers which one was used, and re-renders it when outputting commonmark.

What do you think? I prefer option 3, but if you're really serious about being bug-for-bug compatible with cmark-gfm then maybe 2 is better :shrug:

(Edit: I'd be happy to make a PR for either option 2 or 3. Obviously option 1 doesn't require any changes...)

### Additional contract requirements

The requested resolution for this task is to change the commonmark renderer so that a hard line break (`NodeValue::LineBreak`) is not serialized as a backslash followed by a newline when it occurs at the end of a block. In particular, when a `NodeValue::LineBreak` node has no next sibling, or its next sibling is a block node, the commonmark renderer must not emit a `\` character for that line break. The surrounding block content (for example, the paragraphs before and after the line break) must still be rendered.

Keeping the current behavior (option 1 above) is not an acceptable resolution for this task.

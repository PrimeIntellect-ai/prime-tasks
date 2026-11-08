Extract code form Markdown file and run it
Is it possible to use the `mdq` to extract the markdown code and run it "easily"?

For example I would like to extract all the bash code and run it ideally using:

```
cat test.md | mdq '```bash' -o code | sh -x
```

I have the following MD file:

````
Bash commands:
```bash
...bash commands...
```

Shell commands:
```shell
...shell commands...
```

Fish Commands:
```fish
...fish commands...
```

Outputs:
```console
...default "shell/console/output" commands...
```
````

Then I can use:

```
# Bash
cat my_markdwon_file.md | mdq '```bash' -o plane | bash -x

# Shell
cat my_markdwon_file.md | mdq '```sh' -o plane | sh -x

# Fish
cat my_markdwon_file.md | mdq '```fish' -o plane | fish -x

# Console output (nothing is executed)
cat my_markdwon_file.md | mdq '```console' -o plane

# Show me all command blocks
cat my_markdwon_file.md | mdq -o plane
```

_Originally posted by @ruzickap in https://github.com/yshavit/mdq/discussions/220#discussioncomment-12363984_

### Additional contract requirements

- Provide a `plain` output format selectable with `-o plain`. It must emit selected Markdown code block contents without Markdown fences so the output can be used in a command pipeline.
- With `-o plain`, a paragraph containing `Test _one_ [two][1] three.` followed by a Rust code block containing `some_markdown("rust");` must produce exactly `Test one two three.\n\nsome_markdown("rust");\n`.
- For `-o plain` output, separate table cells in each row with a single space; the rows `Name Description` and `Foo Not a fizz` are examples.

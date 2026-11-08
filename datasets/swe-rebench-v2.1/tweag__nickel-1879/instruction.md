The markdown `nickel doc` output prints some spurious backslashes
**Describe the bug**

`nickel doc`'s markdown output contains some backlashes that mess up with the rendering. For instance, `{ x : Number = 1, y | doc "Blah" }` will be rendered as

```markdown
# `x`

- `x : Number`
\
# `y`

\
Blah
```

`cmark` as well as GitHub's markdown renderer and `pandoc --from=commonmark` will show (some of) these backslashes literally:

![image](https://github.com/tweag/nickel/assets/7226587/c9748cc9-3a5d-46cb-82a8-6e303b95a2d2)

Pandoc's own markdown format won't render them but interpret them as escaping the start of the next line:

![image](https://github.com/tweag/nickel/assets/7226587/3bf0a157-df5e-4577-8fda-9a5a0de4592e)

**To Reproduce**

```console
$ nickel doc --stdout <<<'{ x : Number = 1, y | doc "Blah" }' | cmark
```

**Expected behavior**

An output that is at least commonmark-compatible (and if possible compatible with other common markdown dialects like gfm or pandoc)

**Environment**
 - OS name + version:
 - Version of the code: 28672ee45bfe78dc3dc828ac1fe4fa40f99965e9

**Additional context**
Add any other context about the problem here.

### Additional contract requirements

- For the record-documentation case rendered with the heading `Hello` and documentation `World!`, the `nickel doc --stdout` output must be exactly:

```markdown
# `Hello`

World\!
```

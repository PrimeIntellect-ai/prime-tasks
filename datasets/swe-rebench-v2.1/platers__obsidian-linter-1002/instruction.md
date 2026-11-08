Bug: Move Math Block Indicators to Their Own Line duplicates text before block math delimiter
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

The rule `Move Math Block Indicators to Their Own Line` duplicates text before block math delimiter.

## How to Reproduce

Steps to reproduce the behavior:

1. Create a new vault, enable community plugin, install this linter.
2. Enable `Lint on save` rule for simplicity.
3. Enable `Move Math Block Indicators to Their Own Line` Rule
4. Write `a$$b$$` in the editor.
5. Save (or Lint the file)
6. (Additionally) repeatedly linting the file keeps on duplicating the text before the block math delimiter.

## Expected Behavior

Expected output if applicable:

``` markdown
a
$$
b
$$
```

## Screenshots

https://github.com/platers/obsidian-linter/assets/38686321/b75863cf-5654-452d-ba5b-98d953b11fb2

## Device

- [x] Desktop (MacOS)
- [ ] Mobile

## Additional Context

I checked the source code and found that this is actually a feature for math blocks inside blockquotes (`>`).
For blockquotes,

```
> $$a$$
```

should be linted to

```
> $$
> a
> $$
```

which is probably why the `a` in my example keeps getting duplicated. Is this intended behavior?

### Additional contract requirements

- Applying the rule again to already formatted output must not duplicate text that precedes a math block delimiter.
- When moving the opening `$$` to its own line, remove any spaces or tabs between it and preceding content. For input `a 	    $$b$$`, the output must be:

```markdown
a
$$
b
$$
```

For input `> a 	    $$b$$`, the output must be:

```markdown
> a
> $$
> b
> $$
```

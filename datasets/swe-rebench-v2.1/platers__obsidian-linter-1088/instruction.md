Bug: Indentations for math block removed from callouts or block quotes
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

Hello,

When using math blocks with sublists in a callout or block quote, the indentations for math blocks are removed, which causes the list to be rendered incorrectly. Please see code blocks and screenshots bellow. From a quick search through the issues, I think this might be related to [#289](https://github.com/platers/obsidian-linter/issues/289).

Thanks in advance for the help, and also thanks for maintaining this awesome plugin :)


## How to Reproduce

Example to reproduce the issue with

``` markdown
>[!INFO] Linter sublist latex repro
> text
> - list item 1
>     $$
>     f = ma
>     $$
>     - sublist item 1
>         $$
>         y = ax + b
>         $$
```

On lint, this gets converted to

``` markdown
> [!INFO] Linter sublist latex repro
> text
> - list item 1
> $$
> f = ma
> $$
>     - sublist item 1
> $$
> y = ax + b
> $$
```

Please see my [data.json](https://github.com/platers/obsidian-linter/files/15213830/data.json).

## Expected Behavior

I'm actually not sure what the proper format for using math blocks in lists is, but I expected at least some indentation instead of completely removing them on lint.

The expected output should be should be the same (or similar) as the input

``` markdown
>[!INFO] Linter sublist latex repro
> text
> - list item 1
>     $$
>     f = ma
>     $$
>     - sublist item 1
>         $$
>         y = ax + b
>         $$
```

## Screenshots

Before linting
![Screenshot 2024-05-05 at 1 18 49 PM](https://github.com/platers/obsidian-linter/assets/16347901/a11e4b6e-fb50-4fd4-bf03-8ca6dcad7706)

After linting
![Screenshot 2024-05-05 at 1 19 13 PM](https://github.com/platers/obsidian-linter/assets/16347901/dc051aea-67f1-4aa0-b92f-83006f35755a)


## Device

- [x] Desktop
- [ ] Mobile


## Additional Context

Add any other context about the problem here.

### Additional contract requirements

- The linter must preserve the exact indentation of math block lines inside a blockquote/callout. It must not remove or alter the leading whitespace of the `$$` delimiters or of the math content lines.
- For the reproduction example above, the expected output is exactly the input with a single space inserted after the blockquote indicator on the first line (`>[!INFO] Linter sublist latex repro` becomes `> [!INFO] Linter sublist latex repro`); every other line, including all math block lines, is preserved exactly as in the input.

Bug: "Move Math Block Indicators to Their Own Line" Not Working
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

The `Move Math Block Indicators to Their Own Line` rule did not work for simple cases and it seems related to incorrect `parseTextToAST` result.

## How to Reproduce

Example to reproduce issue with
```markdown
$$a$$

$$
b$$

$$c
$$
```

rule: `move-math-block-indicators-to-their-own-line`

## Expected Behavior

A clear and concise description of what you expected to happen.

Expected output if applicable:

``` markdown
$$
a
$$

$$
b
$$

$$
c
$$
```

## ~~Screenshots~~ Current Output

``` markdown
$$
a
$$

$$
b$$

$$c
$$
```

## Device

- [x] Desktop

## Additional Context

In the function `makeSureMathBlockIndicatorsAreOnTheirOwnLines` in `mdast.ts`, there are `getPositions(MDAstTypes.Math, text)` and `getPositions(MDAstTypes.InlineMath, text)`. I printed the results, and it shows each has 1 element: it recognizes `$$a$$` as an **inline math**, which makes the rule accidentally worked, and it takes line 3-7, that is, the
```markdown
$$
b$$

$$c
$$
```
part as **one** math block, which makes the rule failed. See the console output below (the first array is by `MDAstTypes.Math` and the second one is by `MDAstTypes.InlineMath`).

<img width="408" alt="image" src="https://github.com/platers/obsidian-linter/assets/13874231/a76ba8b3-9d35-4f0a-a004-8f56da87cb25">

Bug: can't insert space between Chinese and math equation correctly
I turn on the function "Space between Chinese and English or numbers" and try to lint the file.

But I found it can only insert a space before a math equation but can't insert a space between the equation.

Sample:

- Before:

```markdown
这是一个数学公式$f(x)=x^2$这是一个数学公式
```

- After：

```markdown
这是一个数学公式 $f(x)=x^2$这是一个数学公式
```
Bug: Inline comment ending a line prevents ignoring of multiline comment later in file
## Describe the Bug

This is related to #223 and #269 and is a minimal repro of the issue I was commenting on at the bottom of #223. Multiline comments are not successfully ignored if an inline comment earlier in the file ends a line. Putting a space between inline comment and linebreak does not fix this, putting text between does.

## How to Reproduce
Set "paragraph blank lines" rule on OR set "two spaces between lines with content" on. (Not both.)

``` markdown
%% fold %%

## R

%%
HW:: --
T:: 0
%%

```


## Expected Behavior
Linter output for the bottom of the file (starting `## R`) should be the same as if the input was:


``` markdown
%% fold %% notComment

## R

%%
HW:: --
T:: 0
%%

```

## Device

- [x] Desktop

Note: The file initially had a second multiline block comment above the inline comment which was successfully ignored by both "paragraph blank lines" and "two spaces between lines with content" rules.
Bug: disabled rules: [all] does not disable YAML Timestamp.
## Describe the Bug

`disabled rules: [all]` does not disable YAML Timestamp.

## How to Reproduce

Steps to reproduce the behavior:

1. Set up the YAML Timestamp like this ![](https://user-images.githubusercontent.com/48207708/180135592-00880f1d-a08f-4b2c-bd71-676d4d803c7a.png)
2. In a note, write `disabled rules: [all]` in the YAML
3. Excute the command `lint current file`
4. The YAML timestamp is still inserted

## Expected Behavior

The YAML timestamp should not be inserted when `disabled rules: [all]` is there.

## Device

- [x] Desktop (macOS)

### Additional contract requirements

For the inline-math example, the prose describes the intended result: add a space before the equation and also between its closing `$` and the following Chinese text. The missing space in the displayed “After” sample is an omission; the required behavior includes that trailing space.

An inline Obsidian comment that ends a line must not cause a later multiline Obsidian comment to be treated as ordinary content by either the Paragraph blank lines rule or the Two spaces between lines with content rule.

When a note's YAML frontmatter contains `disabled rules: [all]`, YAML Timestamp must not add a timestamp, even when YAML Timestamp is enabled in the linter settings.

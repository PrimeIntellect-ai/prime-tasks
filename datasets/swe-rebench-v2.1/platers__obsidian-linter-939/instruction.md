Bug: "Blockquote Style" affects nested non-blockquote ">" symbols
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

When "Content -> Blockquote Style" is enabled, it affects the ">" symbols even when they are not part of the formatting.
A space will be added after them if the style is set to "space".
A space will be removed after them if the style is set to "no space".

## How to Reproduce

This is an example which is affected by the bug when the style is set to "space":

``` markdown
> Using a C++ "member of pointer" operator: `pointer->field`

> `>`
```

Will be turned into:

``` markdown
> Using a C++ "member of pointer" operator: `pointer-> field`

> `> `
```

## Logs

<details>
<summary>Spoiler</summary>

```
Running linter
rules before regular rules: 0.10000000149011612 ms
Running Remove Multiple Spaces
remove-multiple-spaces: 1.8999999985098839 ms

> Using a C++ "member of pointer" operator: `pointer->field`

> `>`

Running Compact YAML
compact-yaml: 0.10000000149011612 ms

> Using a C++ "member of pointer" operator: `pointer->field`

> `>`

Running Empty Line Around Code Fences
empty-line-around-code-fences: 0 ms

> Using a C++ "member of pointer" operator: `pointer->field`

> `>`

Running Empty Line Around Math Blocks
empty-line-around-math-blocks: 0.10000000149011612 ms

> Using a C++ "member of pointer" operator: `pointer->field`

> `>`

Running Empty Line Around Tables
empty-line-around-tables: 0.20000000298023224 ms

> Using a C++ "member of pointer" operator: `pointer->field`

> `>`

Running Heading blank lines
heading-blank-lines: 0.20000000298023224 ms

> Using a C++ "member of pointer" operator: `pointer->field`

> `>`

Running Line Break at Document End
line-break-at-document-end: 0 ms

> Using a C++ "member of pointer" operator: `pointer->field`

> `>`

Running Remove link spacing
remove-link-spacing: 0.09999999403953552 ms

> Using a C++ "member of pointer" operator: `pointer->field`

> `>`

Running Space after list markers
space-after-list-markers: 0.10000000149011612 ms

> Using a C++ "member of pointer" operator: `pointer->field`

> `>`

Running Trailing spaces
trailing-spaces: 0.20000000298023224 ms

> Using a C++ "member of pointer" operator: `pointer->field`

> `>`

Running Custom Regex
custom regex rules: 0 ms
Running Blockquote Style
blockquote-style: 0.09999999403953552 ms

> Using a C++ "member of pointer" operator: `pointer-> field`

> `> `

Running YAML Key Sort
yaml-key-sort: 0.10000000149011612 ms

> Using a C++ "member of pointer" operator: `pointer-> field`

> `> `

rules after regular rules: 0.29999999701976776 ms
rules running: 3.7000000029802322 ms
Running Custom Lint Commands
```

</details>

## Expected Behavior

No change to the document.

## Device

- [x] Desktop
- [x] Mobile (assumed)

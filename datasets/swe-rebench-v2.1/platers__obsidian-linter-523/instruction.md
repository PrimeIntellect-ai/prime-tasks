Bug: Word "I" not Capitalized when First Letter Capitalization Used
## Describe the Bug

"Headings should be formatted with capitalization" lowercases words that should always be capitalized when "First letter" is selected.

In practice, this may only mean the word "I".

## How to Reproduce

Steps to reproduce the behavior:

1. Write a heading such as `### What did I learn?`
2. Lint
3. The heading is changed to `### What did i learn?`

## Expected Behavior

No change, i.e.

```
### What did I learn?
```

## Device

- [ ] Desktop
- [x] Mobile

## Additional Context

I realize I can add "I" to the list of ignored words, but I shouldn't have to.

Bug: No Bare URLs fails if url contains '@' (at)
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

URLs with an '@' symbol in the path are not enclosed completely

## How to Reproduce

Steps to reproduce the behavior:

1. Enable `No Bare URLs` in plugin settings
2. Disable `No Bare URIs` in plugin settings
3. Create a new note
4. Insert `https://domain.org/@user/long-kebab-case-path`
5. Execute command `Lint the current file`
6. The link is not fully enclosed

Or

Example to reproduce issue with

``` markdown
https://domain.org/@user/long-kebab-case-path
```

## Expected Behavior

The full link should be enclosed by angle brackets `<link>`.

Expected output if applicable:

``` markdown
<https://domain.org/@user/long-kebab-case-path>
```

## Actual Behavior

Only a part is enclosed with angle brackets.

Actual output if applicable:

``` markdown
<https://domain.org/>@user/long-kebab-case-path
```

## Screenshots

\-

## Device

- [x] Desktop
- [x] Mobile

## Additional Context

I will provide a PR asap.

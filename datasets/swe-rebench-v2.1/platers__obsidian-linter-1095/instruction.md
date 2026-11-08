Bug: tildes in URLs cause the URL to be broken
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

Whenever the linter encounters a URL with a tilde in, it breaks the URL. It doesn't seem to recognise that `~` is a valid character in a URL.

## How to Reproduce

Steps to reproduce the behavior:

1. Put `<https://some.website/~username/>` into a file
2. Run the linter
3. The result is `<<https://some.website/>~username/>` when the URL should have been left untouched.

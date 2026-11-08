Parse error when a comment is on the same line as a setting
This justfile:

```
set dotenv-load # comment
```

Produces this error:

```
error: Expected '*', ':', '$', '=', identifier, or '+', but found comment
   |
17 | set dotenv-load # comment
   |                 ^^^^^^^^^
```

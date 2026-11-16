Multiline assignments disallow for if statement to follow
Sometimes assignments (function call results) may be split into multiple lines in order to avoid too long lines. In case such statements are used, linter does not allow an `if` statement to follow. Since the `if` statement is closely related to the operation, it should still be allowed for the `if` to follow an assignment that is split into multiple lines.

Allowed:
```go
err := functionCall(arg1, arg2)
if err != nil {
    return err
}
```

Not allowed:
```go
err := functionCall(
    arg1, arg2,
)
if err != nil {
    return err
}
```

### Additional contract requirements

- Expose a boolean `AllowMultiLineAssignmentCuddled` field on `Configuration`. When false, a multiline assignment cannot be cuddled with a following `if`; when true, it may be cuddled if the `if` uses a variable assigned by that assignment. A processor created with the ordinary default configuration allows this cuddling by default.

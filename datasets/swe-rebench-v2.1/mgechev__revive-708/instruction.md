Extra empty line at the end of a block because that empty line is a comment
(i am currently in the process of adding "revive" to our linter stack and i am going through the false-positives for us)

**Describe the bug**

```go
{
   some code

   // comment
}
```

leads to "extra empty line at the end of a block" even though it shouldn't.

**Expected behavior**

Such comments are meant for exactly being at that location. Marking the comment as a probem, is a false-positive for our source code.

### Additional contract requirements

- When reporting an extra empty line at the end of a block, report the diagnostic at the block's opening brace.

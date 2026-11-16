Include stdout/stderr in `error.message`
We removed it in `execa` v2 for some reason, but it's very useful.

The lack of it leads to a lot of annoyance and makes it harder for users to see what actually went wrong...

It also makes it harder to do test assertions like this:

```js
test('missing file operands', async t => {
	await t.throwsAsync(execa('./cli.js'), /`source` and `destination` required/);
});
```

Open questions:
- Should we include `stdout` or only `stderr`?
- Should we truncate it at some length?

### Additional contract requirements

When a failed child process has captured output, its error message must include both captured `stderr` and captured `stdout`.

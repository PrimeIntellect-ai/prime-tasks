Enforce the amount of whitespace surrounding keywords.
Given the following tab-indented source code:

```js
function foo() {
	if (true) {
		try {
			bar();
		}
		catch (err)
		{
			baz();
		}
	}
}
```

Using `brace-style` to use `"1tbs"`, we end up with tabs around the `catch` keyword.

```js
function foo() {
	if (true) {
		try {
			bar();
		}		catch (err)		{
			baz();
		}
	}
}
```

It doesn't seem possible to fix this with the existing eslint rules:

* `keyword-spacing` only asserts that there's a non-zero amount of whitespace around keywords
* `no-multi-spaces` ignore tabs
* `no-tabs` isn't useful because we're using tabs for indentation too

Possible solutions:

* add an option to `keyword-spacing` to enforce exactly one space (my suggestion)
* add an option to `no-tabs` to only flag tabs that aren't at the beginning of the line (suggested by @platinumazure)
* generalise `no-multi-spaces` to work for arbitrary whitespace, not just spaces

Tested on eslint 3.10.2.

### Additional contract requirements

- When `brace-style` autofixes brace placement, it must use exactly one space between a brace and an adjacent keyword. For example, `try { \n bar(); \n }\ncatch (e) {\n}` must be fixed to `try { \n bar(); \n } catch (e) {\n}`.
- When `brace-style` autofixes an opening brace to follow the preceding token on the same line, it must use exactly one space between that token and the brace.

no-unused-vars highlights at wrong position
With `no-unused-vars` enabled eslint highlights the last use of the variable. If it is used left and right of an assignment it should mark the one on the left.

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
Instead of this:
```js
let x = [];
x = x.concat(x);
             ^
```

**What did you expect to happen?**
It should be this:
```js
let x = [];
x = x.concat(x);
^
```

**What actually happened? Please copy-paste the actual, raw output from ESLint.**


**Steps to reproduce this issue:**
1. [eslint demo](https://eslint.org/demo#eyJ0ZXh0IjoibGV0IHggPSBbXTtcbnggPSB4LmNvbmNhdCh4KTsiLCJvcHRpb25zIjp7InBhcnNlck9wdGlvbnMiOnsiZWNtYVZlcnNpb24iOjEyLCJzb3VyY2VUeXBlIjoic2NyaXB0IiwiZWNtYUZlYXR1cmVzIjp7fX0sInJ1bGVzIjp7ImNvbnN0cnVjdG9yLXN1cGVyIjoyLCJmb3ItZGlyZWN0aW9uIjoyLCJnZXR0ZXItcmV0dXJuIjoyLCJuby1hc3luYy1wcm9taXNlLWV4ZWN1dG9yIjoyLCJuby1jYXNlLWRlY2xhcmF0aW9ucyI6Miwibm8tY2xhc3MtYXNzaWduIjoyLCJuby1jb21wYXJlLW5lZy16ZXJvIjoyLCJuby1jb25kLWFzc2lnbiI6Miwibm8tY29uc3QtYXNzaWduIjoyLCJuby1jb25zdGFudC1jb25kaXRpb24iOjIsIm5vLWNvbnRyb2wtcmVnZXgiOjIsIm5vLWRlYnVnZ2VyIjoyLCJuby1kZWxldGUtdmFyIjoyLCJuby1kdXBlLWFyZ3MiOjIsIm5vLWR1cGUtY2xhc3MtbWVtYmVycyI6Miwibm8tZHVwZS1lbHNlLWlmIjoyLCJuby1kdXBlLWtleXMiOjIsIm5vLWR1cGxpY2F0ZS1jYXNlIjoyLCJuby1lbXB0eSI6Miwibm8tZW1wdHktY2hhcmFjdGVyLWNsYXNzIjoyLCJuby1lbXB0eS1wYXR0ZXJuIjoyLCJuby1leC1hc3NpZ24iOjIsIm5vLWV4dHJhLWJvb2xlYW4tY2FzdCI6Miwibm8tZXh0cmEtc2VtaSI6Miwibm8tZmFsbHRocm91Z2giOjIsIm5vLWZ1bmMtYXNzaWduIjoyLCJuby1nbG9iYWwtYXNzaWduIjoyLCJuby1pbXBvcnQtYXNzaWduIjoyLCJuby1pbm5lci1kZWNsYXJhdGlvbnMiOjIsIm5vLWludmFsaWQtcmVnZXhwIjoyLCJuby1pcnJlZ3VsYXItd2hpdGVzcGFjZSI6Miwibm8tbWlzbGVhZGluZy1jaGFyYWN0ZXItY2xhc3MiOjIsIm5vLW1peGVkLXNwYWNlcy1hbmQtdGFicyI6Miwibm8tbmV3LXN5bWJvbCI6Miwibm8tb2JqLWNhbGxzIjoyLCJuby1vY3RhbCI6Miwibm8tcHJvdG90eXBlLWJ1aWx0aW5zIjoyLCJuby1yZWRlY2xhcmUiOjIsIm5vLXJlZ2V4LXNwYWNlcyI6Miwibm8tc2VsZi1hc3NpZ24iOjIsIm5vLXNldHRlci1yZXR1cm4iOjIsIm5vLXNoYWRvdy1yZXN0cmljdGVkLW5hbWVzIjoyLCJuby1zcGFyc2UtYXJyYXlzIjoyLCJuby10aGlzLWJlZm9yZS1zdXBlciI6Miwibm8tdW5kZWYiOjIsIm5vLXVuZXhwZWN0ZWQtbXVsdGlsaW5lIjoyLCJuby11bnJlYWNoYWJsZSI6Miwibm8tdW5zYWZlLWZpbmFsbHkiOjIsIm5vLXVuc2FmZS1uZWdhdGlvbiI6Miwibm8tdW51c2VkLWxhYmVscyI6Miwibm8tdW51c2VkLXZhcnMiOjIsIm5vLXVzZWxlc3MtY2F0Y2giOjIsIm5vLXVzZWxlc3MtZXNjYXBlIjoyLCJuby13aXRoIjoyLCJyZXF1aXJlLXlpZWxkIjoyLCJ1c2UtaXNuYW4iOjIsInZhbGlkLXR5cGVvZiI6Mn0sImVudiI6e319fQ==)

**Are you willing to submit a pull request to fix this bug?**
No

### Additional contract requirements

- When reporting an otherwise-unused recursive function declaration, locate the diagnostic on the declared name; for `function foo(n) { ... return n * foo(n - 1); }`, this is line 1, column 10.
- For an otherwise-unused variable whose initializer is a self-referencing function expression or arrow function, report the diagnostic at its declared name: for `var a = function() { a(); };` and `var a = function(){ return function() { a(); } };`, line 1, column 5; for `const a = () => { a(); };` and `const a = () => () => { a(); };`, line 1, column 7.

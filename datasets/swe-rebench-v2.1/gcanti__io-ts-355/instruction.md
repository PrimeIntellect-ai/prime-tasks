RangeError: Maximum call stack size exceeded
## 🐛 Bug report

### Current Behavior

`RangeError: Maximum call stack size exceeded`

### Expected behavior

No error

### Reproducible example

https://stackblitz.com/edit/typescript-3kmxjd

### Suggested solution(s)

Memoisation, Tail Call Optimisation, Trampolining
https://blog.logrocket.com/using-trampolines-to-manage-large-recursive-loops-in-javascript-d8c9db095ae3/

### Additional context

The code in this example is generated using io-ts-codegen.
This code is used to decode forms that are shown to the user to be filled using angular components.

### Your environment

Which versions of io-ts are affected by this issue?

io-ts@2.0.0

Did this work in previous versions of io-ts?

Not as far as I know.

<!-- PLEASE FILL THIS OUT -->

| Software   | Version(s) |
| ---------- | ---------- |
| io-ts      |      2.0.0      |
| fp-ts      |      2.0.3      |
| TypeScript |  3.4.5+          |

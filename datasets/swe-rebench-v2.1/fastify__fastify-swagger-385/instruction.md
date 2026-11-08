Since #372 underscore char in param is buggy
## 🐛 Bug Report

Since #372, when I use `_` in parameters name, parameters are not well placed in bracket.

`/example/:my_param` => `/example/{my}_param`

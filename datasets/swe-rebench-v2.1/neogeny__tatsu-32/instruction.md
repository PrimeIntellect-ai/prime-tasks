Parser drops part of input
Grammar:
```
identifier = /\w+/ ;
start = '{' start '}' | start '->' identifier | identifier ;
```

Input:
```
{ size }
test
```

Expected output: `['{', 'size', '}']`
Actual output: `test`

Removing the (left recursive) rule `start '->' identifier` fixes the problem.

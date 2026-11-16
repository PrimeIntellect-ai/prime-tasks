Update with nested array slicing behavior difference
Using nested slicing on LHS of update operator causes behavior difference against jq.
```
❯ jq -nc '[1,2,3] | .[1:][:1] = [5]'
[1,5,3]

❯ xq -nc '[1,2,3] | .[1:][:1] = [5]'
[1,5]

❯ xq --version
xq 0.1.9-b5d6c8d747459413aadf8298237f1628edbbd9e7
```

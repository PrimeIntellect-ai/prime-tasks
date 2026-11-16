Cannot cast to duration
`duration` was forgotten when we added primitive casts a while back:

```
$ echo {}  | zq -t "put a=1 | cut a=a:duration" -
rhs of assigment expression: cast to 'duration' not implemented
```

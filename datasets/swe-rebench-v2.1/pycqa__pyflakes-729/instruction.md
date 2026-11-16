annotated variable hides "undefined name"
this works:

```console
$ pyflakes /dev/stdin <<< 'x = x'
/dev/stdin:1:5: undefined name 'x'
$
```

this does not:

```console
$ pyflakes /dev/stdin <<< 'x: int = x'
$
```

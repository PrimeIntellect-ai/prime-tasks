Misleading error message with multiple names
### Bug report

```
$ kn service update echo echo1 --image duglin/echo
requires the service name
```

### Expected behavior

I would have expected either something like:
```
$ kn service create echo echo1 --image duglin/echo
'service create' requires the service name given as single argument
```
or for it to do the update on both services (I kind of like this option).

### Steps to reproduce the problem

See above

### kn version

master/head as of 2020/03/26

### Additional contract requirements

- When `kn service update` is invoked with more than one service name, it must either fail with the error message `'service update' requires the service name given as single argument`, or perform the update on both services.
- When `kn service create` is invoked with more than one service name, it must fail with the error message `'service create' requires the service name given as single argument`.

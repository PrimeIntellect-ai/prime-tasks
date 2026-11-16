Infinite loop revalidateCall
In version 0.7.0

```
Uncaught (in promise) RangeError: Maximum call stack size exceeded
    at revalidateCall (use-swrv.js?a598:187)
    at revalidateCall (use-swrv.js?a598:187)
    at revalidateCall (use-swrv.js?a598:187)
...
```

https://github.com/Kong/swrv/blob/master/src/use-swrv.ts#L221

[HIDDEN]

should probably be

[HIDDEN]

### Additional contract requirements

- When revalidation is requested, it should perform revalidation and complete without an infinite recursive loop or stack overflow.

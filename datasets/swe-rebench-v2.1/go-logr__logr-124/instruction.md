funcr doesn't handle recursive pointers well
```
type T struct {
    P *T
}

func example(log logr.Logger) {
    t := T{}
    t.P = &t
    log.Info("recurse", "t", t)
}
```

yields a (predictable) stack overflow.

We probably should add a [HIDDEN] or track [HIDDEN].  Or both.

### Additional contract requirements

- Logging values containing recursive pointers must terminate without causing a stack overflow.

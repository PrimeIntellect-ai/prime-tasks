Result of multiple decorations of the same type depends on invocation order
Consider:

```go
type A struct {
	name string
}

c := dig.New()
child := c.Scope("child")
c.Provide(func() *A { return &A{name: "A"} })

c.Decorate(func(a *A) *A { return &A{name: a.name + "'"} })
child.Decorate(func(a *A) *A { return &A{name: a.name + "'"} })

c.Invoke(func(a *A) {
    fmt.Println(a.name)
})

child.Invoke(func(a *A) {
    fmt.Println(a.name)
})
```

This prints `A''` and `A'` respectively to the console.

Now let's say the invokes were reversed in order:
```go
child.Invoke(func(a *A) {
    fmt.Println(a.name)
})

c.Invoke(func(a *A) {
    fmt.Println(a.name)
})
```
That ends up printing `A'` and `A'` on the screen.

The order of invocation should not alter the committed value - this is likely a bug in the paramSingle.Build() logic where it's being too "lazy" with the lookups for decorated values.

Case arms should be considered for intersecting variables
Most statements that has a block as a condition, e.g. `if [condition]` or `for range [condition]`. For `switch` statements we check what we're switching on, e.g. `switch [condition]` but I think we should also consider the arms the same way.

Today, this is not allowed:

```go
myVariable := someFn()
switch [condition without myVariable] {
case isGood(myVariable):
    // ...
case isBad(myVariable):
    // ...
}
```

Since they're so closely tied together and in the same context, I think it would make sense to allow this. By doing so, we would also support the same pattern with anonymous `switch`:

```go
myVariable := 42
switch {
case myVariable < 10:
    // ...
case myVariable == 10:
   // ...
case myBariable > 10:
   // ...
}
```

This would also apply for ~~type switches and~~ `select`:

```go
ctx := someCtx()
select {
case ctx.Done():
    // ...
case time.After(time.Minute):
    // ...
}
```

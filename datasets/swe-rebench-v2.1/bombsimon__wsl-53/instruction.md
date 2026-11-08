Support multiple go-statements
I think it should be allowed to cuddle multiple go statements if they're on a single line like this:

```go
t1 := CreateT()
t2 := CreateT()
t2 := CreateT()

go t1.Func()
go t2.Func()
go t3.Func()
```

Today the alternatives would be:

```go
t1 := CreateT()
t2 := CreateT()
t2 := CreateT()

go t1.Func()

go t2.Func()

go t3.Func()
```

Or

```
t1 := CreateT()
go t1.Func()

t2 := CreateT()
go t2.Func()

t2 := CreateT()
go t3.Func()
```

But the last one is not reasonable if we have to do mor things with `tn`, e.g.

```go
t1 := CreateT()
t1.SetX(1)
t1.SetY(2)

go t1.Func()
```

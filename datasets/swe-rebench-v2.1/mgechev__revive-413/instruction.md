new rule: unconditional-recursion
Unconditional recursive calls will produce infinite recursion, thus program stack overflow.
Even if it seems that the frequency of such errors is low, autocompletion functionality of IDEs facilitates them. A typical case is:

```go
type myType struct {
  field int
}

func (mt myType) Field() int {
  return mt.Field()          // /!\ recursive call in place of accessing mt.field
}
```

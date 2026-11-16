Expression should validate rule result is an expression
## Summary

As reported on the [pyomo-forum](https://groups.google.com/g/pyomo-forum/c/x3IEN3ybp9M/m/Wc3msdBTAgAJ), `Expression` components do not validate that the result from the rule is actually a valid numeric expression.  In particular, the following does not produce an error (but should):

### Steps to reproduce the issue

```python
model = ConcreteModel()
model.TIME = RangeSet(2)
model.x = Var(model.TIME)
@model.Expression(model.TIME)
def exp1(m, t):
    return m.x[t]

@model.Expression(model.TIME)
def exp2(m, t):
    return m.exp1

model.pprint()
```

```
1 RangeSet Declarations
    TIME : Dimen=1, Size=2, Bounds=(1, 2)
        Key  : Finite : Members
        None :   True :   [1:2]

1 Var Declarations
    x : Size=2, Index=TIME
        Key : Lower : Value : Upper : Fixed : Stale : Domain
          1 :  None :  None :  None : False :  True :  Reals
          2 :  None :  None :  None : False :  True :  Reals

2 Expression Declarations
    exp1 : Size=2, Index=TIME
        Key : Expression
          1 :       x[1]
          2 :       x[2]
    exp2 : Size=2, Index=TIME
        Key : Expression
          1 :       exp1
          2 :       exp1

4 Declarations: TIME x exp1 exp2
```

### Additional contract requirements

- When an Expression rule returns an object that is not a valid numeric expression, construction must raise TypeError with a message containing `is not a valid type for Pyomo numeric expressions`.

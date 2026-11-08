"Invalid font operand "1.0 1" for Tf Operator" when font dictionary key contains other font operator
Simple reproduction:
```
/Tc1.0 1 Tf
```

As "Tc" is also a valid operator, it is parsed here as the operator, removing it from the operand buffer.

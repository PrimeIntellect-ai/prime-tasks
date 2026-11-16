badCond: reports wrong suspicious condition
Found a bug in `badCond`:

```
if paramType == lastParam.GetType() && paramType == bgp.BGP_ASPATH_ATTR_TYPE_SEQ {
```

Which indeed looks suspicious but here is the thing: `GetType()` might return `BGP_ASPATH_ATTR_TYPE_SEQ` which is a correct behaviour.

I think in `badCond` we should compare only simple/pure/safe expressions.

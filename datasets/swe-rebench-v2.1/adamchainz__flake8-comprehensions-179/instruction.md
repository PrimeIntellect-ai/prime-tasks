Sum list vs generator comprehesion detection with startpoint arg
So right now the linter highlights this:
```sum([x + 1 for x in range(30)])``` and for all the right reasons.
However, this isn't detected right now:
```sum([x + 1 for x in range(30)], 0)```

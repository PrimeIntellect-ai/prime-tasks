Optimizer: implement "remove duplicates" transform for disjunction
It would be nice if the optimizer removed duplicates in disjunctions:

`/ab|ab/ -> /ab/`

### Additional contract requirements

The regular-expression optimizer must remove duplicate alternatives as part of its normal optimization behavior; callers should not need to invoke a separate transform.

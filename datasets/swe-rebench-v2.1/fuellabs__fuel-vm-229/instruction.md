`RETD` has off-by-one for overflow check.
If `RETD` tries to return a buffer wedged right at the top of RAM (i.e., where the heap grows down from) then it will erroneously throw a `MemoryOverflow`.

Type instability when iterating nested recursive arrays
I noticed that the following is type unstable (on v3.3.3 and julia 1.10.0)

```julia
using RecursiveArrayTools

sum(ArrayPartition(ArrayPartition(zeros(4,4)))) # ::Any

sum(VectorOfArray([zeros(4), VectorOfArray([zeros(4,4)])])) # ::Any
```

Curiously, all of the following are stable.
```julia
sum(ArrayPartition(ArrayPartition(zeros(4)))) # ::Float64
sum(ArrayPartition(zeros(4,4))) # ::Float64

sum(VectorOfArray([VectorOfArray([zeros(4,4)])])) # ::Float64
```

The other recursive array types seem to be affected as well. Not sure if getting these stable is in-scope, but it would be super helpful.

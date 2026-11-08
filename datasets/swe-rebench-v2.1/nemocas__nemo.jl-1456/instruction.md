digits not padding "0" correctly
The digits function is not padding the result correctly for input "0". It simply returns a vector of length 1 in this case no matter what the padding is set to. This does not match the behavior for Base.digits.
```
julia> digits(ZZ(0), base = 2, pad = 8)
1-element Vector{Int64}:
 0

julia> digits(0, base = 2, pad = 8)
8-element Vector{Int64}:
 0
 0
 0
 0
 0
 0
 0
 0
```

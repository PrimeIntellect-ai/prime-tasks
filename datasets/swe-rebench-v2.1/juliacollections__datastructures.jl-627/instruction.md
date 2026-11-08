Absence of merge() in RobinDict
The absence of `merge` method call for RobinDict leads to the following problem.
```julia
julia> using DataStructures

julia> rd1 = RobinDict()
RobinDict{Any,Any} with 0 entries

julia> for i=1:10
           rd1[i] = 2*i
       end

julia> rd2 = RobinDict()
RobinDict{Any,Any} with 0 entries

julia> for i=11:20
           rd2[i] = 2*i + 1
       end

julia> merge(rd1, rd2)
Dict{Any,Any} with 20 entries:
  18 => 37
  2  => 4
  16 => 33
  11 => 23
  7  => 14
  9  => 18
  10 => 20
  19 => 39
  17 => 35
  8  => 16
  6  => 12
  4  => 8
  3  => 6
  5  => 10
  20 => 41
  13 => 27
  14 => 29
  15 => 31
  12 => 25
  1  => 2
```
`merge(rd1, rd2)` should have been of the type `RobinDict`.

### Additional contract requirements

- `merge(d::RobinDict, others::RobinDict...)` returns a new `RobinDict` whose key and value types are the promoted types of all input dictionaries, and whose entries are the union of the inputs' entries. When the same key appears in more than one input, the value from the later argument overwrites the earlier one.
- `merge(combine::Function, d::RobinDict, others::RobinDict...)` returns a new `RobinDict` with promoted key and value types; for a key present in multiple inputs, the resulting value is `combine(old_value, new_value)` applied in argument order.
- Both methods accept one or more additional `RobinDict` arguments.

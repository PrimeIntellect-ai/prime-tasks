Copy in Array constructor from DenseAxisArray
This does not make a copy:
https://github.com/jump-dev/JuMP.jl/blob/a157e4c8c4b2db4ce8bbd360b058a5e9fc32dabe/src/Containers/DenseAxisArray.jl#L27
while https://docs.julialang.org/en/v1/manual/conversion-and-promotion/#Mutable-collections says that `convert` may not copy but a constructor should always copy.

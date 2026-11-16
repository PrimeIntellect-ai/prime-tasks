Broadcasting over multiple DenseAxisArrays
While trying to set up the initial point for a problem, the following problem occur.
no method matching set_start_value(::JuMP.Containers.DenseAxisArray{VariableRef,1,Tuple{Array{String,1}},Tuple{Dict{String,Int64}}}, ::JuMP.Containers.DenseAxisArray{Float64,1,Tuple{Array{String,1}},Tuple{Dict{String,Int64}}})

In attach a sample of the code
[report_error.txt](https://github.com/jump-dev/JuMP.jl/files/4891964/report_error.txt)

### Additional contract requirements

Elementwise broadcasting involving multiple `DenseAxisArray` values must be usable, including when nested in another broadcast expression. The result remains a `DenseAxisArray` and preserves the axes' labels so values can be retrieved by those labels.

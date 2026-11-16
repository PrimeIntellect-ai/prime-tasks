Type Constraints in the Rule Structs
I was working on getting Optimisers to work with reactant, and it (mostly) does, but one of the current issues is that `eta` is forced to be Float64 in some of the structs.

But consider the following IR:

```julia
julia> pss = (; a = (rand(3) |> Reactant.to_rarray))
(a = ConcreteRArray{Float64, 1}([0.023549009580651203, 0.10813549621409191, 0.7874517465499301]),)

julia> st_opt = @allowscalar Optimisers.setup(opt, pss)
(a = Leaf(Adam(0.001, (0.9, 0.999), 1.0e-8), (ConcreteRArray{Float64, 1}([0.0, 0.0, 0.0]), ConcreteRArray{Float64, 1}([0.0, 0.0, 0.0]), (0.9, 0.999))),)

julia> @code_hlo Optimisers.update(st_opt, pss, pss)
module {
  func.func @main(%arg0: tensor<3xf64>, %arg1: tensor<3xf64>, %arg2: tensor<3xf64>) -> (tensor<3xf64>, tensor<3xf64>, tensor<3xf64>) {
    %cst = stablehlo.constant dense<1.000000e-03> : tensor<3xf64>
    %cst_0 = stablehlo.constant dense<1.000000e-08> : tensor<3xf64>
    %cst_1 = stablehlo.constant dense<0.0010000000000000009> : tensor<3xf64>
    %cst_2 = stablehlo.constant dense<0.99899999999999999> : tensor<3xf64>
    %cst_3 = stablehlo.constant dense<0.099999999999999978> : tensor<3xf64>
    %cst_4 = stablehlo.constant dense<9.000000e-01> : tensor<3xf64>
    %0 = stablehlo.multiply %cst_4, %arg0 : tensor<3xf64>
    %1 = stablehlo.multiply %cst_3, %arg2 : tensor<3xf64>
    %2 = stablehlo.add %0, %1 : tensor<3xf64>
    %3 = stablehlo.multiply %cst_2, %arg1 : tensor<3xf64>
    %4 = stablehlo.abs %arg2 : tensor<3xf64>
    %5 = stablehlo.multiply %4, %4 : tensor<3xf64>
    %6 = stablehlo.multiply %cst_1, %5 : tensor<3xf64>
    %7 = stablehlo.add %3, %6 : tensor<3xf64>
    %8 = stablehlo.divide %2, %cst_3 : tensor<3xf64>
    %9 = stablehlo.divide %7, %cst_1 : tensor<3xf64>
    %10 = stablehlo.sqrt %9 : tensor<3xf64>
    %11 = stablehlo.add %10, %cst_0 : tensor<3xf64>
    %12 = stablehlo.divide %8, %11 : tensor<3xf64>
    %13 = stablehlo.multiply %12, %cst : tensor<3xf64>
    %14 = stablehlo.subtract %arg2, %13 : tensor<3xf64>
    return %2, %7, %14 : tensor<3xf64>, tensor<3xf64>, tensor<3xf64>
  }
}
```

While this looks correct, if you take a closer look:

```
%cst_1 = stablehlo.constant dense<0.0010000000000000009> : tensor<3xf64>
%cst_2 = stablehlo.constant dense<0.99899999999999999> : tensor<3xf64>
%cst_3 = stablehlo.constant dense<0.099999999999999978> : tensor<3xf64>
```

The learning rate and the other parameters get embedded into the IR as constants. So even if we do an `adjust` of the learning rate, it will still be using the old learning rate

### Additional contract requirements

- Numeric rule parameters such as the learning rate `eta` must not be forced to `Float64`. A supplied value of a compatible type, such as a `Float32` learning rate, must keep that type, for example `Optimisers.Adam(0.1f0).eta isa Float32`.
- After a rule's learning rate is changed with `Optimisers.adjust` or `Optimisers.adjust!`, later calls to `Optimisers.update` must apply the adjusted learning rate rather than the previous value.

`isapprox` failing for `TrackedReal`
Hi all,

I'm currentlyplaying with bayesian NNs, and I'm slowly building up from the basic [example given on the Turing.jl website](https://turing.ml/dev/tutorials/3-bayesnn/), now trying to extend the classification from being binary to multiclass. Thus, I defined the output of my BNN as a `Categorical` instead of a `Binomial`. Logically enough, `Categorical` requires samples to be probability vector, positive and summing to one, _i.e._, from Distributions/src/utils.jl:


```
isprobvec(p::AbstractVector{<:Real}) =
    all(x -> x ≥ zero(x), p) && isapprox(sum(p), one(eltype(p)))
```

Naturally, output of the `Flux.softmax` of a vector is not exactly 1.0 due to floating points shenanigans, but `isapprox` takes care of that.

The problem however, is that what works with floats doesn't seem to work with `TrackedReal`:

```
xx = ReverseDiff.TrackedReal{Float64,Float64,ReverseDiff.TrackedArray{Float64,Float64,2,Array{Float64,2},Array{Float64,2}}}[TrackedReal<4WI>(0.42766067643153494, 0.0, 3Wk, ---), TrackedReal<FB4>(0.1639909617549507, 0.0, 3Wk, ---), TrackedReal<49W>(0.4083483618135143, 0.0, 3Wk, ---)]
sum(xx) = TrackedReal<KQ5>(0.9999999999999999, 0.0, 3Wk, ---)
one(eltype(xx)) = TrackedReal<HSG>(1.0, 0.0, ---, ---)
isapprox(sum(xx), 1.0) = true
isapprox(sum(xx), one(eltype(xx))) = false
isprobvec(r[:, i]) = false
```


So `xx`, the output of my network, is indeed a “very close to sum-to-one” vector of `TrackedReal` (`xx = [0.427..., 0.163..., 0.408...]`); its sum is a “very-close-to-one” `TrackedReal` (`sum = TrackedReal(0.9999999999999999, ...)`), it is virtually equal to `Float64(1.0)` (`isapprox(sum(xx), 1.0) = true`), **but**, it's not very close to the `one` of its type: `isapprox(sum(xx), one(eltype(xx))) = false`. Hence, it's not a probability vector, and it is rejected by `Categorical`.

[Here is a minimal failing program from which the above example is extracted; if you run it as is under Julia 1.5, you should encounter my problem](https://gist.github.com/delehef/2895d5e95935bf158c6221c6b9d46f10)

Did I miss something and are tracked reals failing to compare similar to one a normal behaviour, or is there a bug somewhere?

### Additional contract requirements

With default tolerances, approximate comparison of two `TrackedReal` values should reflect the closeness of their underlying real values: close values compare approximately equal, while materially different values do not.

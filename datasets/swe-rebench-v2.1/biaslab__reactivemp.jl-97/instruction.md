Outgoing BP rules for :var interface of NormalMeanVariance node.
### Discussed in https://github.com/biaslab/ReactiveMP.jl/discussions/95

Hi guys,
(@ismailsenoz @semihakbayrak @bvdmitri)
How sure we are about the BP message for `:var` interface that is associated with variance?

We had a look a few days ago with @bartvanerp and it seemed to us that the normalization of the message is incorrect.
I see there are tests for these rules, but I am still concerned about some missing factors in:
```julia
ContinuousUnivariateLogPdf(DomainSets.HalfLine(), (x) -> -log(m_μ_cov + x) / 2 - 1 / (2x) * (m_out_mean - m_μ_mean) ^ 2)
```


There is an issue with BP message from `GaussianMeanVariance` node. The correct version when both `:mean` and `:out` inbounds messages are Gaussians should be:
```
(x) -> -log(m_μ_cov + m_out_cov + x) / 2 - 1 / (2*(m_μ_cov + m_out_cov + x)) * (m_out_mean - m_μ_mean) ^ 2)
```

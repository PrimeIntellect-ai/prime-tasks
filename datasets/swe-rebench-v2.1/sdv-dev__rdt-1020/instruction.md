Add a fallback distribution in `GaussianNormalizer` in case the given distribution fails
### Problem Description
The [GaussianNormalizer RDT](https://docs.sdv.dev/rdt/transformers-glossary/numerical/gaussiannormalizer) estimates the shape of a marginal distribution using scipy, and then performs an inverse CDF transform to return a normal distribution.

As noted in [SDV #2391](https://github.com/sdv-dev/SDV/issues/2391), the requested scipy distribution may sometimes fail to converge for reasons that are outside of our control. In such cases, [GaussianCopula](https://github.com/sdv-dev/Copulas/blob/main/copulas/multivariate/gaussian.py#L123) typically falls back to using the normal distribution.

It would be nice if GaussianNormalizer could do the same. That way, any synthesizer that is dependent on it can proceed without crashing.

### Expected behavior
Update the GaussianNormalizer fall back to using `'norm'` if something goes wrong. The fallback distribution cannot officially be changed by the user (via a parameter) but we should keep it as an attribute so it's accessible:

```python
>>> transformer = GaussianNormalizer(distribution='beta')
>>> transformer._fallback_distribution
'norm'
```

- During `fit`, we should use the `_fallback_distribution` if anything goes wrong in scipy.  If this happens, log it (logger.INFO) the same way that we do for Copulas.
- After fitting, it should be possible to access the learned parameters via an attribute. The returned values should be similar to GaussianCopulaSynthesizer's [get_learned_distributions](https://docs.sdv.dev/sdv/single-table-data/modeling/synthesizers/gaussiancopulasynthesizer#get_learned_distributions) function.
- If the fallback is used, make sure to update the name of the distribution from the originally requested distribution (eg. `'beta'`) to the fallback distribution (eg. `'norm'`)

```python
>>> transformer.learned_distribution
{
  'distribution': 'norm',
  'parameters': { 'loc': 2.100, 'scale': 0.12121 } # these keys vary based on the distribution name
}
```

### Additional Context
This would resolve the CopulaGANSynthesizer bug in [SDV #2391](https://docs.sdv.dev/sdv/single-table-data/modeling/synthesizers/gaussiancopulasynthesizer#get_learned_distributions).

### Additional contract requirements

- Use this exact fallback INFO message format: `Unable to fit the distribution '{distribution}'. Falling back to '{fallback_distribution}'.` Substitute the distribution name in effect for fitting and the fallback name; for example, a failed `beta` fit logs `Unable to fit the distribution 'beta'. Falling back to 'norm'.`

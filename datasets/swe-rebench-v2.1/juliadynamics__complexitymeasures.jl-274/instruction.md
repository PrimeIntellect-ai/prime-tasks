Identification entropy
**Describe the feature you'd like to have**

In [Alswhede (2021)](https://link.springer.com/content/pdf/10.1007/978-3-030-65072-8.pdf) book on page 375, the *identification entropy* is defined.

The formula can straight-forwardly be defined for a set of `Probabilities`, and should be easy to implement.

### Additional contract requirements

Provide the entropy definition under the public name `Identification`, usable with the package's entropy API. Given a `Probabilities` vector `p`, its entropy is `2 * (1 - sum(p_i^2))`.

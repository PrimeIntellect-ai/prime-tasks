Add velocity dispersion function sampler to skypy
## Description
Add a velocity dispersion function sampler to skypy, which is describes the populations of lenses in sigma_v space. Sigma_v is velocity dispersion of the lens. The equation used for this is found in [Choi et al. (2017)](https://iopscience.iop.org/article/10.1086/511060/pdf). The paper uses data of Elliptical galaxies from the Sloan Digital Sky survey.
## Inputs

Minimum sigma_v, maximum sigma_v, resolution of function, size (number of samples to be returned)

## Outputs

Samples drawn from VDF function

## References
[Choi et al. (2017)](https://iopscience.iop.org/article/10.1086/511060/pdf)

### Additional contract requirements

Add a public function `schechter_vdf(alpha, beta, vd_star, vd_min, vd_max, size=None, resolution=1000)` in module `skypy.galaxies.velocity_dispersion`.

- `alpha` (float or int): the Schechter alpha parameter.
- `beta` (float or int): the Schechter beta parameter.
- `vd_star` (float): the characteristic velocity dispersion sigma_*.
- `vd_min` (float): lower bound of the velocity-dispersion range.
- `vd_max` (float): upper bound of the velocity-dispersion range.
- `size` (int, optional): number of samples to draw.
- `resolution` (int, optional): resolution of the sampling spline.

The function returns a `numpy.ndarray` of velocity-dispersion values sampled from the modified Schechter velocity-dispersion function. Every returned value lies within the closed interval [`vd_min`, `vd_max`], and the number of returned values equals `size` when `size` is provided.


- For `alpha=2.32`, `beta=2.67`, `vd_star=161`, `vd_min=1`, `vd_max=300`, `size=5000`, and `resolution=3000`, when the NumPy random seed is set with `np.random.seed(0)`, the samples must yield a one-sample Kolmogorov–Smirnov goodness-of-fit p-value greater than `1e-4` against the normalized modified Schechter distribution.

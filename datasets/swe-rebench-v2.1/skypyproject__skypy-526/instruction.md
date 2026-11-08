ENH: Rykoff apparent magnitude uncertainty of galaxies
## Description
Add a function that returns the uncertainty of the galaxies' apparent magnitude in the given filter bands as described by equation (6) in Rykoff et al. (2015). Note: the normalisation constant k is absorbed in the included in parameter t_eff

## Inputs
 - Apparent magnitudes
 - 10 sigma apparent magnitude limits
 - Parameters a and b of the model
 - Uncertainty limit

## Outputs
 - Apparent magnitude uncertainty of galaxies

## References
- Rykoff et al. (2015), Assessing galaxy limiting magnitudes in large optical surveys, [arXiv 1509.00870](https://arxiv.org/abs/1509.00870)

### Additional contract requirements

Expose the calculation as `magnitude_error_rykoff` in `skypy.utils.photometry`. It accepts `magnitude`, `magnitude_limit`, `magnitude_zp`, `a`, and `b`, with an optional `error_limit` argument. The caller must be able to supply the survey magnitude zero point (`magnitude_zp`) used to calculate the fluxes. Return the apparent-magnitude uncertainty from equation (6) of Rykoff et al. (2015), capped at `error_limit` when supplied.

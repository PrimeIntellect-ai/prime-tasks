Error in calculation for 2D-slinear interpolator.
### Description

Getting some wrong values when compared against slinear or scipy_slinear. Seems to be a mistake in the calculations.

### Example

The function in our test doesn't have enough variation to show the problem. This one is a better example: `f_p = np.cos(P1 * P2 / 360.0) + (0.01 * P1 * P2) ** 2`

### OpenMDAO Version

3.30.1-dev

### Relevant environment information

_No response_

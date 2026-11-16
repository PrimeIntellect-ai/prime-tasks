Inconsistency with error formulae in AveragedCrossspectrum
### Description of the Issue

The errors on the cross spectrum are typically calculated with `error_on_averaged_cross_spectrum`, which checks whether one is using a common reference band or not. However, the `phase_lag` and `time_lag` methods in `AveragedCrossspectrum` always just assume the latter (ie, it's always eq. 14 in Ingram 2019, even if sometimes eq. 19 would be the correct one).

### Your suggestions for the Fix

_No response_

### Additional contract requirements

When constructing an averaged cross spectrum, callers must be able to indicate whether the reference band includes the subject-band photons using the `channels_overlap` boolean argument. The uncertainties returned with `phase_lag` and `time_lag` must use the formula appropriate to that relationship.

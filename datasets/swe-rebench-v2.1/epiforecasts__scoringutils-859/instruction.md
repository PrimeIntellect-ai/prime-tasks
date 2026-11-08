Improve error handling for `wis()`
Consider the following example:

`observed <- 0.1`
`predicted <- 0.1032978 0.1078166 0.1906849 0.1969254 0.2017249 0.2078487 0.2810377 0.3062168 0.4006721 0.8219655`
`quantile_level <- 0.600 0.650 0.700 0.750 0.800 0.850 0.900 0.950 0.975 0.990`

This gives `Error in eval(jsub, SDenv, parent.frame()) : object 'lower' not found` which is not very informative.

We should check that at least one valid interval remains

### Additional contract requirements

- If no valid forecast intervals remain, `wis()` must raise an error containing `No valid forecast intervals found.`

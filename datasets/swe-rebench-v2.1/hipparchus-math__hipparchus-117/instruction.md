Add Møller's 2Sum algorithm
Add Møller's 2Sum algorithm based on discussion [here](https://gitlab.orekit.org/orekit/orekit/-/merge_requests/149).

### Additional contract requirements

- Expose the operation for two `double` inputs through `MathUtils.twoSum(double, double)`, returning `MathUtils.SumAndResidual`. The returned result must make both the rounded sum and its residual rounding error available through `getSum()` and `getResidual()`, respectively.
- For finite inputs whose rounded sum is finite, the residual must equal the exact real sum of the inputs minus the rounded sum, not merely be a nonzero estimate.

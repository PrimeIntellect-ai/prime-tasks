[Bug] Batch-indexing lazy covariance matrix fails for batch-mode ExactGP
# 🐛 Bug

Evaluating a batch-mode ExactGP with training inputs of shape `b x n x d` and targets of shape `b x n` on a set of test points with shape `m x d` yields a lazy_covariance_matrix with shape `b x m x m`. Indexing along the batch dimension fails.

## To reproduce

[batch_indexing_bug_lazy_covar.ipynb.txt](https://github.com/cornellius-gp/gpytorch/files/3331406/batch_indexing_bug_lazy_covar.ipynb.txt)

## Expected Behavior

Selecting a single index of the batch dimension:

```
mvn.lazy_covariance_matrix[0, :, :]
```
should yield the lazy covariance matrix for the 0th batch (with shape `m x m`)

## System information
- <!-- GPyTorch Version (run `print(gpytorch.__version__)` --> 0.3.2
- <!-- PyTorch Version (run `print(torch.__version__)` --> 1.0.0a0

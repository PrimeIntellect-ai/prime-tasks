Flag to turn off logdet computations for MLLs
For exact and variational GPs, the marginal log likelihood requires computing the log determinant of the prior covariance matrix. This isn't a super expensive operation (since we get most of the terms for free from a single call to `linear_cg`). However, we still have to make a few calls to `torch.symeig`, which can add a bit of a performance hit.

If we are simply using the MLL as a loss function to optimize hyperparameters (and not for Gibbs sampling, model selection, etc.), then we don't actually care about the logdet value (just its derivatives, which we get for free from `linear_cg`). Therefore, we could avoid these `torch.symeig` calls.

I propose a `gpytorch.beta_features.skip_logdet` feature flag that skips the logdet computation (but still computes the correct gradient, obviously). It will be off by default.

### Additional contract requirements

- The feature flag is exposed as `gpytorch.settings.skip_logdet_forward`, a context manager that takes a boolean value and is disabled by default.
- `LazyTensor.inv_quad_log_det(inv_quad_rhs=None, log_det=False)` returns a tuple `(inv_quad_term, log_det_term)`. When `log_det=True` and `skip_logdet_forward` is enabled, `log_det_term` is a zero tensor with the same shape as the lazy tensor's batch shape, the forward log-determinant computation is not performed, and the gradients of both returned terms remain correct.

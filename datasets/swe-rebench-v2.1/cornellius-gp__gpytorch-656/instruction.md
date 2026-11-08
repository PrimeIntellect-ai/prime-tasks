ValueError: NonLazyTensor expects a matrix (or batches of matrices) - got a Tensor of size torch.Size([50]).
# 🐛 Bug

Hi,
I encounter an error when running SVGP with an additive kernel, which did not happen to me when using gpytorch 0.2.1.
```
~/anaconda3/envs/gpytorch2/lib/python3.6/site-packages/gpytorch/variational/whitened_variational_strategy.py in forward(self, x)
    188
    189             if self.training:
--> 190                 data_covariance = DiagLazyTensor((data_data_covar.diag() - interp_data_data_var).clamp(0, math.inf))
    191             else:
    192                 neg_induc_data_data_covar = induc_induc_covar.inv_matmul(
```

** Code snippet to reproduce **
```python
class SVGPRegressionModel(gpytorch.models.AbstractVariationalGP):
    def __init__(self, inducing_points):
        variational_distribution = gpytorch.variational.CholeskyVariationalDistribution(10)
        variational_strategy = gpytorch.variational.WhitenedVariationalStrategy(self, inducing_points, variational_distribution, learn_inducing_locations=True)
        super(SVGPRegressionModel, self).__init__(variational_strategy)
        self.mean_module = gpytorch.means.ZeroMean()
        self.covar_module = gpytorch.kernels.ScaleKernel(gpytorch.kernels.RBFKernel() + gpytorch.kernels.MaternKernel(nu=2.5))

    def forward(self, x):
        mean_x = self.mean_module(x)
        covar_x = self.covar_module(x)
        return gpytorch.distributions.MultivariateNormal(mean_x, covar_x)

x = torch.randn(50, 2)
z = torch.randn(10, 2)
model = SVGPRegressionModel(z)
output = model(x)
```

### Additional contract requirements

When an additive kernel is evaluated for its diagonal, the returned values must equal the elementwise sum of the diagonal values from each component kernel, including when the components use different kernel types.

The supplied SVGP example must be able to evaluate `model(x)` successfully with its scaled additive covariance kernel.

ARX with exogenous variable forecasts residual variance is not as expected
```
import numpy as np
import pandas as pd
import arch
from arch.univariate import Normal as ARCHNormal

seed = 42
np.set_printoptions(precision=3, suppress=True, linewidth=100, floatmode='fixed')

test_df = pd.DataFrame({'y':np.array([0,7,2,5,9,3,8]).astype(float), 'x':np.arange(7).astype(float)})
y = test_df['y'].values
x = test_df['x'].values

test_model = arch.arch_model(y=test_df['y'], x=test_df['x'], mean='ARX', vol='GARCH', lags=1, p=1, q=0, rescale=False)
y_coeff = 0.3   # lag 1 coefficient for AR(1) process
x_coeff = 0.2   # coefficient for exogenous variable
res_coeff = 0.5 # lag 1 coefficient for volatility process
start = 1       # start from second observation
test_model.distribution = ARCHNormal(seed=seed)
test_res = test_model.fix([0., y_coeff, x_coeff, 0., res_coeff]) # constants set to zero
sims = test_res.forecast(horizon=1, start=start, method='simulation', simulations=1, x=x[:,np.newaxis], align='origin')
means = sims.mean.values.squeeze()
vars = sims.variance.values.squeeze()
expected_means = y_coeff*y + x_coeff*x # calculate expected means
eps = y[start:] - expected_means[start-1:-1] if start > 0 else y[1:] - expected_means[:-1] # calculate residuals

# eps = eps - x_coeff # NOTE: adding this line aligns the residuals with the variance otherwise, it does not match

values = sims.simulations.values.squeeze()
print(f'y:              {y[start:]}')
print(f'x:              {x[start:]}')
print(f'Expected means: {expected_means[start:]}')
print(f'Actual means:   {means}')
print(f'Residuals:      {eps}')
print(f'Expected vars:  {res_coeff*(eps**2)}')
print(f'Actual vars:    {vars}')
```
The above code tries to simulate a AR(1) with 1 exogenous variable with a GARCH(1,0) volatility process with horizon=1 and start=1. Unexpectedly, the residual variance does not align with expectations unless the coefficient for the exogenous variable is subtracted from the residual from the previous time step i.e. eps = eps - x_coeff.

### Additional contract requirements

For the ARX model with an exogenous variable described above (GARCH(1, 0) with omega = 0), the forecast variance at each forecast origin must equal the volatility coefficient times the squared residual at that origin: `variance[t] = res_coeff * resid[t]**2`, where `resid[t]` is the residual of the fixed-parameter result at time `t`. No exogenous-coefficient adjustment to the residual is required.

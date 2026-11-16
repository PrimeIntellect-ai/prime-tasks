Error in SUR with a constraint if `q` is used
Thanks for a great package. In the following SUR code with a constraint , an error occurs if `q` is used in `model.add_constraints(r, q)`, but no error for `model.add_constraints(r)`. I know that `q` is optional and `q` is set to zero if it is not used. But I thought it might be a good idea to report this.

```
from linearmodels.system import SUR
import pandas as pd
import numpy as np

n = 100
x1 = np.random.normal(size=n)
x2 = np.random.normal(size=n)
x3 = np.random.normal(size=n)

y1 = 3 + 1.5 * x1 - 2.0 * x2 + np.random.normal(size=n)
y2 = -1 + 0.5 * x2 + 1.2 * x3 + np.random.normal(size=n)

data = pd.DataFrame({'x1': x1, 'x2': x2, 'x3': x3, 'y1': y1, 'y2': y2})

equations = {
    'eq1': 'y1 ~ x1 + x2',
    'eq2': 'y2 ~ x2 + x3'
}

model = SUR.from_formula(equations, data)

# coefficients of eq1_x1 and eq2_x2 are equal
r = pd.DataFrame([[0]*4],
                 columns=model.param_names,
                 index=["rest"],
                 dtype=np.float64)
r.iloc[0,0] = -1
r.iloc[0,2] = 1

# ERROR occurs if q is used
# the error remains if the value other `0` is used.
# q = pd.Series([0])
# model.add_constraints(r, q)

# No error without q
model.add_constraints(r)

results = model.fit()
```

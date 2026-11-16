RuntimeError when converting GaussianProcessRegressor with WhiteKernel and return_std option
### Description
When attempting to convert a scikit-learn GaussianProcessRegressor model with WhiteKernel to ONNX format using the `return_std=True` option, the conversion fails with a RuntimeError. The error occurs specifically when using the WhiteKernel, while the conversion works fine when the option is removed.

### Error Message
```
RuntimeError: Unable to convert diag method for class <class 'sklearn.gaussian_process.kernels.WhiteKernel'>.
```

Here is an example code to reproduce the error:

```python
import numpy as np
from sklearn.gaussian_process import GaussianProcessRegressor
from sklearn.gaussian_process.kernels import WhiteKernel
import onnx
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType

# Generate sample data
X = np.array([[1], [3], [5], [6], [7], [8], [10], [12], [14], [15]])
y = np.array([3, 2, 7, 8, 7, 6, 9, 11, 10, 12])

# Define the kernel
kernel = WhiteKernel()

# Create and train the Gaussian Process Regressor
gpr = GaussianProcessRegressor(kernel=kernel, n_restarts_optimizer=10, alpha=1e-2)
gpr.fit(X, y)

# Convert the trained model to ONNX format
initial_type = [("float_input", FloatTensorType([None, 1]))]
onnx_model = convert_sklearn(
    gpr,
    initial_types=initial_type,
    options={GaussianProcessRegressor: {"return_std": True}},
)
```

### Environment Information
- Operating System: MacOS 15.2
- Python Version: 3.10.14
- scikit-learn Version: 1.5.0
- skl2onnx Version: 1.18.0
- onnx Version: 1.17.0

Thank you in advance for any feedback or solution!

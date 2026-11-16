QDA converter throws an error when used with string labels
`QuadraticDiscriminantAnalysis` converter crashes when using string labels. The shape calculator for the labels is also wrong.

## Typerror with string labels
To reproduce the error, run the following code (shortened version of the first QDA [test](https://github.com/onnx/sklearn-onnx/blob/acfa6a47ea111ecb93774d62cde0dfbbd669c7ca/tests/test_sklearn_quadratic_discriminant_analysis_converter.py#L28) ):
```python
import numpy as np
from sklearn.discriminant_analysis import QuadraticDiscriminantAnalysis
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import DoubleTensorType

X = np.array([[-1, -1], [-2, -1], [-3, -2], [1, 1], [2, 1], [3, 2]])
y = np.array(["a", "a", "a", "b", "b", "b"])

skl_model = QuadraticDiscriminantAnalysis()
skl_model.fit(X, y)

onnx_model = convert_sklearn(
    skl_model,
    "scikit-learn QDA",
    [("input", DoubleTensorType([None, X.shape[1]]))],
    target_opset=16,
)
```
Output:
`TypeError: Unable to make a tensor name='classes' onnx_type=7 shape=[2] content-type=<class 'numpy.ndarray'>.`

Note: `LinearDiscriminantAnalysis` model does not fail on this case


## Wrong shape calculator
The `QuadraticDiscriminantAnalysis`  shape calculator is  wrong in the following line:
https://github.com/onnx/sklearn-onnx/blob/acfa6a47ea111ecb93774d62cde0dfbbd669c7ca/skl2onnx/shape_calculators/quadratic_discriminant_analysis.py#L9
 The first output should have shape `[1, None] `and not `[1, N]`, where `N` is the number of labels.

This leads to a warning during inference:
```python
import numpy as np
from sklearn.discriminant_analysis import QuadraticDiscriminantAnalysis
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import DoubleTensorType
import onnxruntime

X = np.array([[-1, -1], [-2, -1], [-3, -2], [1, 1], [2, 1], [3, 2]])
y = np.array([0, 0, 0, 1, 1, 1])

skl_model = QuadraticDiscriminantAnalysis()
skl_model.fit(X, y)

onnx_model = convert_sklearn(
    skl_model,
    "scikit-learn QDA",
    [("input", DoubleTensorType([None, X.shape[1]]))],
    target_opset=16,
    options={"zipmap": False},
)


sess = onnxruntime.InferenceSession(
    onnx_model.SerializeToString(), providers=["CPUExecutionProvider"]
)

sess.run(None, {"input": X.astype(np.double)})
```
Output:
`[W:onnxruntime:, execution_frame.cc:870 VerifyOutputSizes] Expected shape from model of {1,2} does not match actual shape of {1,6} for output label`

#### Package versions:
```
python==3.9.21
numpy==1.24.3
sklearn==1.6.1
skl2onnx==1.18.0
onnxconverter_common==1.13.0
onnx==1.13.1
onnxruntime==1.19.2
```

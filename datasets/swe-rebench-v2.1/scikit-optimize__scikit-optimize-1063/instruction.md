Scikit-optimize master GaussianProcessRegressor is incompatible with scikit-learn 1.0
`scikit-learn` 0.19 depreciated the `y_train_mean` attribute of `GaussianProcessRegressor`. At the time it was made private, and so scikit-optimize continued to rely on it. #467 was never merged to properly fix that.
Scikit-learn 1.0 removed the attribute, breaking scikit-optimize.

**Version**
- `python==3.9.2`
- `scikit-learn==1.0`
- `scikit-optimize==0.9.dev0` (installed with `pip install git+https://github.com/scikit-optimize/scikit-optimize.git`)

**How to reproduce**
```bash
mkdir test
cd test
python3 -m venv venv
source venv/bin/activate
pip install "scikit-learn==1.0" git+https://github.com/scikit-optimize/scikit-optimize.git
```

Write the following script to `test.py`:
```python
import scipy
import sklearn
import skopt
from sklearn import model_selection, svm
from sklearn.datasets import load_digits

print("scipy:", scipy.__version__)
print("scikit-learn:", sklearn.__version__)
print("scikit-optimize:", skopt.__version__)

X, y = load_digits(n_class=10, return_X_y=True)
X_train, X_test, y_train, y_test = model_selection.train_test_split(
    X, y, train_size=0.75, test_size=0.25, random_state=0
)

opt = skopt.BayesSearchCV(
    svm.SVC(),
    {
        "C": (1e-6, 1e6, "log-uniform"),
        "gamma": (1e-6, 1e6, "log-uniform"),
        "kernel": ["linear", "rbf"],
    },
    n_iter=32,
    cv=3,
)

opt.fit(X_train, y_train)
print("Best train score:", opt.best_score_)
print("Tests score:", opt.score(X_test, y_test))
```

and run it in the test venv:
```bash
python test.py
```

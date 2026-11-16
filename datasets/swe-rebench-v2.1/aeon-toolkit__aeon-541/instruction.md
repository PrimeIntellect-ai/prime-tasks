[BUG]
### Describe the bug

An error with Numba(ConstantInferenceError) is preventing me to use clustering.

### Steps/Code to reproduce the bug

from aeon.clustering.k_means import TimeSeriesKMeans

# This is a just a list of numpy arrays
with open('dataCluster100.pkl', 'rb') as f:
        dataCluster99 = pickle.load(f)

X_train = np.array([arr[np.newaxis, :] for arr in dataCluster99])

k_means = TimeSeriesKMeans(
    n_clusters=13,  # Number of desired centers
    init_algorithm="forgy",  # Center initialisation technique
    max_iter=10,  # Maximum number of iterations for refinement on training set
    metric="dtw",  # Distance metric to use
    averaging_method="dba",  # Averaging technique to use
    random_state=1,
)

k_means.fit(X_train)

### Expected results

N/A

### Actual results

ConstantInferenceError                    Traceback (most recent call last)
[<ipython-input-5-2c4a67d93a28>](https://localhost:8080/#) in <cell line: 15>()
     13 )
     14
---> 15 k_means.fit(X_train)

6 frames
[/usr/local/lib/python3.10/dist-packages/numba/core/dispatcher.py](https://localhost:8080/#) in error_rewrite(e, issue_type)
    407                 raise e
    408             else:
--> 409                 raise e.with_traceback(None)
    410
    411         argtypes = []

ConstantInferenceError: Failed in nopython mode pipeline (step: nopython rewrites)
Constant inference not possible for: $const288.2 + $292format_value.5

File "../usr/local/lib/python3.10/dist-packages/aeon/clustering/metrics/averaging/_barycenter_averaging.py", line 137:
def _ba_update(
    <source elided>
        else:
            [HIDDEN]
            ^

### Versions

<details>
System:
    python: 3.10.12 (main, Jun  7 2023, 12:45:35) [GCC 9.4.0]
executable: /usr/bin/python3
   machine: Linux-5.15.107+-x86_64-with-glibc2.31

Python dependencies:
          pip: 23.1.2
   setuptools: 67.7.2
      sklearn: None
         aeon: 0.3.0
  statsmodels: 0.13.5
        numpy: 1.22.4
        scipy: 1.10.1
       pandas: 1.5.3
   matplotlib: 3.7.1
       joblib: 1.2.0
        numba: 0.56.4
     pmdarima: None
      tsfresh: None
</details>

### Additional contract requirements

- The DBA (elastic barycenter) averaging must not fail with a Numba
  `ConstantInferenceError`; the reported `TimeSeriesKMeans.fit` reproduction must
  complete without raising.
- When the DBA averaging is given a metric string it does not support, it must raise
  a `ValueError` whose message is `Metric parameter invalid`.

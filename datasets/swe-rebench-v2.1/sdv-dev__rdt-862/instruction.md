Lazy import BayesianGaussianMixture from sklearn
### Problem Description

_As a user, I'd like import times to be quick._
As of now, anytime a user imports anything from RDT, all of the modules are imported. Certain modules scan be slow. The numerical module is especially slow because it takes time to import the `BayesianGaussianMixture` as can be seen in this log file that can be viewed using tuna.

[base_sdv_import_times.log](https://github.com/user-attachments/files/16534623/base_sdv_import_times.log)

### Expected behavior

- Running `import rdt` should be significantly faster

### Additional context

- Check to make sure performance tests aren't way worse. Maybe we can import in the init instead of the fit

### Additional contract requirements

- Importing the ``rdt`` package must not import ``sklearn.mixture``.
- The ``BayesianGaussianMixture`` dependency must be imported only when functionality that requires it is used.

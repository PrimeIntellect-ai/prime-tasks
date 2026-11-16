Possible bug: correlation.template_correlate throws an error if given Spectrum1D objects with no flux uncertainties defined.
OS: Mac 12.7.1
Python: 3.11.6
specutils: 1.11.0

Issue:
I am attempting to use the `template_correlate()` function like so:
`corr1, lag1 = correlation.template_correlate(obs_spec_loglin, model_1_loglin, resample=False)`

Here, `obs_spec_login` and `model_1_loglin` are both Spectrum1D objects. They do not have flux uncertainties defined. I run into the following error, which appears to be due to line 245, part of `_normalize()`, not handling the case where flux uncertainties are not assigned to the Spectrum1D object?

File "/Users/fleming/anaconda3/envs/py311/lib/python3.11/site-packages/specutils/analysis/correlation.py", line 77, in template_correlate
    normalization = _normalize(observed_log_spectrum, template_log_spectrum)
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/fleming/anaconda3/envs/py311/lib/python3.11/site-packages/specutils/analysis/correlation.py", line 245, in _normalize
    unc = observed_spectrum.uncertainty.represent_as(StdDevUncertainty)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
AttributeError: 'NoneType' object has no attribute 'represent_as'

Bug in new inputs report for empty arrays
### Description

See the error report below.  The new inputs report takes the minimum value of an input, but this gives an error for an empty array:
```
535 14:42 gbarter-37067s:~/devel/WISDEM/examples/02_reference_turbines $python iea15mw_driver.py
Traceback (most recent call last):
  File "/Users/gbarter/devel/WISDEM/examples/02_reference_turbines/iea15mw_driver.py", line 11, in <module>
    wt_opt, analysis_options, opt_options = run_wisdem(fname_wt_input, fname_modeling_options, fname_analysis_options)
  File "/Users/gbarter/devel/WISDEM/wisdem/glue_code/runWISDEM.py", line 177, in run_wisdem
    wt_opt.run_model()
  File "/Users/gbarter/devel/OpenMDAO/openmdao/core/problem.py", line 837, in run_model
    self.final_setup()
  File "/Users/gbarter/devel/OpenMDAO/openmdao/utils/hooks.py", line 132, in execute_hooks
    _run_hooks(post_hooks, inst)
  File "/Users/gbarter/devel/OpenMDAO/openmdao/utils/hooks.py", line 108, in _run_hooks
    hook(inst, **kwargs)
  File "/Users/gbarter/devel/OpenMDAO/openmdao/visualization/inputs_report/inputs_report.py", line 170, in _run_inputs_report
    inputs_report(prob, display=False, outfile=path,
  File "/Users/gbarter/devel/OpenMDAO/openmdao/visualization/inputs_report/inputs_report.py", line 115, in inputs_report
    vcell, mincell, maxcell = _get_val_cells(val)
  [HIDDEN]
  File "<__array_function__ internals>", line 180, in amin
  File "/opt/local/Library/Frameworks/Python.framework/Versions/3.9/lib/python3.9/site-packages/numpy/core/fromnumeric.py", line 2918, in amin
    return _wrapreduction(a, np.minimum, 'min', axis, None, out,
  File "/opt/local/Library/Frameworks/Python.framework/Versions/3.9/lib/python3.9/site-packages/numpy/core/fromnumeric.py", line 86, in _wrapreduction
    return ufunc.reduce(obj, axis, dtype, out, **passkwargs)
ValueError: zero-size array to reduction operation minimum which has no identity
```

### Example

```python
Set an empty numpy array as an initial value for an OpenMDAO input (`np.array([])`)
```


### OpenMDAO Version

3.22.1-dev

### Relevant environment information

First noticed on Github actions worker for windows & linux, but successfully recreated locally on a Mac with macports.

### Additional contract requirements

- For an empty NumPy input array, the inputs report must display `[]` in the `Val`, `Min Val`, and `Max Val` cells.

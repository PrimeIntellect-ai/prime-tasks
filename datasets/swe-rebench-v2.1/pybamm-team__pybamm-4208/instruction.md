Better error on unrecognised parameter set
Doing `pybamm.ParameterValues("bad")` gives `ValueError: Invalid Parameter Value`. It would be better to say something like `ValueError: 'bad' is not a recognised parameter set` and possibly list the valid options (including custom parameter sets that have been registered as entry points).

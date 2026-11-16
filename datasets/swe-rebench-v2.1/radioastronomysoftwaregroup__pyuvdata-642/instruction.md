baselines_to_antums is not vectorized
Seems you can't give a list of baseline numbers and get a list of antenna pair tuples.  That would be useful.

### Additional contract requirements

- `uvutils.baseline_to_antnums(baseline, Nants_telescope)` accepts a scalar or array-like of baseline numbers and returns the corresponding first and second antenna numbers, each as a scalar or array-like.
- `UVData.baseline_to_antnums(baseline)` provides the same behavior using the object's `Nants_telescope`.
- `uvutils.antnums_to_baseline(ant1, ant2, Nants_telescope, attempt256=False)` accepts scalar or array-like antenna numbers and returns the corresponding baseline numbers as a scalar or array-like.
- `UVData.antnums_to_baseline(ant1, ant2, attempt256=False)` provides the same behavior using the object's `Nants_telescope`.

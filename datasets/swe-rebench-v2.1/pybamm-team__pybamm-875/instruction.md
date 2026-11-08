Search parameters and variables
As @TomTranter suggests there are a lot of variables and parameters, and we should add a search function. This could be done in `pybamm.FuzzyDict`. We could search for keys containing the word a user searches for, and then provide best matches if there are no results.

### Additional contract requirements

- `pybamm.FuzzyDict` (in `pybamm.util`) has a public method `search(key, print_values=False)`. It searches the dictionary keys for those that contain `key` as a substring, matching case-insensitively. By default it prints the matching keys; when `print_values=True` it prints each matching key together with its value. When no key matches, it prints best-match suggestions instead. It returns `None`.
- `pybamm.ParameterValues` (in `pybamm.parameters.parameter_values`) has a public method `search(key, print_values=True)`. It searches the parameter names for those that contain `key` as a substring. By default it prints each matching parameter name together with its value; when `print_values=False` it prints only the matching parameter names. It returns `None`.


- - When searching a dictionary with keys `Electrolyte concentration` and `Electrode potential` using `bad var`, the printed best-match suggestions include both keys.

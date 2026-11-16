CaseReader.list_outputs method should handle missing data more gracefully
### Description

Currently when the `CaseReader.list_outputs` method is called, if a requested type of data, for example, residuals, is not recorded, the method raises an Exception and does not continue. The error shown is

```
   outputs = case.list_outputs(
             ^^^^^^^^^^^^^^^^^^
 File "./openmdao/recorders/case.py", line 1024, in list_outputs
   resids = self.residuals[name]
            ~~~~~~~~~~~~~~^^^^^^
 TypeError: 'NoneType' object is not subscriptable
 ```

 A better user experience would be for the `list_outputs` method to continue collecting information that can get and also print a user friendly warning.


### Example

```
import openmdao.api as om

filename = "problem_history.db"

cr = om.CaseReader(filename)
case = cr.get_case("final")
outputs = case.list_outputs(
   explicit=True,
   implicit=True,
   val=True,
   residuals=True,
   residuals_tol=None,
   units=True,
   shape=True,
   bounds=True,
   desc=True,
   scaling=False,
   hierarchical=True,
   print_arrays=True,
   out_stream=None,
   return_format="dict",
)
```

### OpenMDAO Version

3.33.1-dev

### Relevant environment information

_No response_

### Additional contract requirements

When `list_outputs` is called with `residuals=True` (or with a `residuals_tol`) but the residuals
were not recorded, the method must not raise. It must continue to return and display the output
information that is available, and it must indicate the missing residuals in its output by
displaying the text `Not Recorded` in the residuals column (this is the user friendly warning
referred to above).

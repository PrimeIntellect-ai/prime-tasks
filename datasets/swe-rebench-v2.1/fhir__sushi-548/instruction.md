Whitespace in Resource references is not handled correctly
When using a Resource reference, the grammar allows for whitespace to be inside the `()`, but the spaces are not handled properly. The two examples below illustrate this:


If you have the following rule in your FSH
```
* subject = Reference(   mCODEPatientExample01 )
```
the output will be
```
"reference": "   mCODEPatientExample01 "
```
No errors are logged in this case, but this is not the intended output.

Additionally, if you have the following rule in your FSH
```
* stage.assessment only Reference(   CancerStageParent )
```
SUSHI logs the following error and skips the rule:
```
error No definition for the type "   CancerStageParent " could be found.
```

[VASP] [Bug] Second posmap error does not change SYMPREC
When the VASP `"posmap"` error occurs twice, [SYMPREC should be changed to 1e-4](https://github.com/materialsproject/custodian/blob/master/custodian/vasp/handlers.py#L413). However, it stays 1e-6 [HIDDEN] A test was also not written for the second SYMPREC error handler.

Edit: Will be closed when #183 is merged.

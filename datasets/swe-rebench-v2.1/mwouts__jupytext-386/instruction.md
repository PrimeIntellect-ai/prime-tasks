Jupytext --execute fails in subfolder
If I test/execute a notebook in a subfolder, then the notebook can't read files located in the same subfolder - it seems that Jupytext executes the notebook from its current directory instead.

### Additional contract requirements

When executing a notebook in a subfolder, relative file accesses must resolve against that folder so the notebook can read files stored there. This applies both to text notebooks converted for execution and to existing `.ipynb` files.

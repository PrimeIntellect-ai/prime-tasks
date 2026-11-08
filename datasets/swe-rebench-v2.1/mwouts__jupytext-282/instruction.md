`jupytext --sync` should ignore unpaired notebooks
Using v1.1.7, when doing `jupytext --sync *.ipynb`, an exception is thrown when it encounters an unpaired notebook. (https://github.com/mwouts/jupytext/blob/1.1.7/jupytext/cli.py#L446) However, it would be better if unpaired notebooks were skipped.

### Additional contract requirements

- When an unpaired notebook is skipped, `jupytext --sync` should write a warning to stderr containing the exact text `is not a paired notebook`.

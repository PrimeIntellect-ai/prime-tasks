Upgrade from traitlets `5.11.2` to `5.12.0` broke script
## Context
I noticed that a script that we use as part of our CI workflow stopped working with the update from traitlets `5.11.2` to `5.12.0`.

The script in question: https://github.com/awslabs/syne-tune/blob/main/.github/workflows/utils/notebooks2scripts.py#L8

Relevant lines:
```python
from traitlets.config import Config
from nbconvert.exporters import PythonExporter

c = Config()
c.TagRemovePreprocessor.remove_cell_tags = "ci-skip-cell"
python_exporter = PythonExporter(config=c)
```

The script converts Jupyter notebooks into Python scripts that our CI can execute, to make sure that our notebooks work correctly. For more about our use-case, refer to the PR that added it: https://github.com/awslabs/syne-tune/pull/756

We have been using traitlets to skip specific Jupyter notebook cells that have been tagged with a special `ci-skip-cell` tag ([example](https://github.com/awslabs/syne-tune/blob/main/examples/notebooks/tune_xgboost.ipynb?short_path=9a34c5a#L22)). The reason for skipping specific cells is because we found that attempting to convert notebooks with `%pip install` cells did not work. What we are doing is instead installing the dependencies ahead of time in our CI environment, and then running the rest of the converted script.

<img width="358" alt="Screenshot 2023-10-30 at 11 20 53 PM" src="https://github.com/ipython/traitlets/assets/1182047/a58984f0-a556-4e22-ac28-bc90a6a74b53">

## Problem

Before the update to `5.12.0`, running the conversion script would skip the cells tagged with `ci-skip-cell`, however after the update, the cells have stopped being skipped.

Converted script before updating:
```
#!/usr/bin/env python
# coding: utf-8

# # Tune XGBoost

# ### Install dependencies
#

# In[ ]:

... (truncated)
```

Converted notebook after the update:

```
#!/usr/bin/env python
# coding: utf-8

# # Tune XGBoost

# ### Install dependencies
#

# In[ ]:


get_ipython().run_line_magic('pip', "install 'syne-tune[basic]'")
get_ipython().run_line_magic('pip', 'install xgboost')


# In[ ]:


... (truncated)
```

Note the two additional `get_ipython` lines that we do not want to see.

PR reverting to `5.11.2` makes all of the test pass again: https://github.com/awslabs/syne-tune/pull/782

Example test run where they were failing: https://github.com/awslabs/syne-tune/actions/runs/6693658169

## Question

Is the new traitlets behavior expected?

### Additional contract requirements

- The public `Set` trait type is importable from `traitlets`.
- Assigning a plain string to a `Set` trait stores a set containing that whole string as a single element (for example, assigning `"ab"` stores `{"ab"}`), rather than a set of the string's individual characters.
- Assigning any other value to a `Set` trait stores that value unchanged, subject to the element type.
- `Set(trait_type)` constructs a set trait whose elements must conform to `trait_type`; assigning a set that contains an element which does not conform to `trait_type` raises `TraitError`.

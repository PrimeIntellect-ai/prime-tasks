Unexpected unnest-sideeffect in Dataset.save_preprocessed()
## Current Behavior
When calling `Dataset.save_preprocessed()` with `extension='csv'` columns need to be unnested before saving.
This part is definitely intended. But it is unexpected that the columns stay unnested after the call.

The user now needs to call `nest` again if they want to run preprocessing functions.

## Expected Behavior
The saving of the dataset should not alter any dataframe.
[HIDDEN]

## Minimum acceptance criteria
- [ ] no side-effects on GazeDataFrame during saving.

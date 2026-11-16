Criteria table from datastack archive produced by HRA doesn't work
To reproduce:

1. Open up the 3.12+ version of HRA (the one with the datastack override for spatial criteria)
2. Load this datastack (Stanford auth required): https://drive.google.com/file/d/1tqheKjtekvNxavlB9FekCqtCycLIQZDX/view?usp=sharing
3. Observe a validation error in the criteria table saying the table can't be opened as a CSV

The workaround for now is to:

1. Extract the datastack somewhere
2. Open the criteria table CSV in Excel
3. Save the CSV to a new location as a CSV.
4. Update the UI to use the new path
5. The input validates as expected and the model runs.

### Additional contract requirements

When an HRA datastack is extracted, its criteria-table CSV must be usable directly: validation should succeed and the model should be able to run without resaving the CSV or changing any path in the table.

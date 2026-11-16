`select_units` fails in `SortingAnalyzer` after using `load_sorting_analyzer`
## Problem

After saving a sorter (to binary_folder) and then reloading, you can no longer use the `select_units` function.

## MRE

```python
rec, sorting = si.generate_ground_truth_recording()
analyzer = si.create_sorting_analyzer(sorting, rec, format = 'binary_folder', folder='./test')
analyzer.compute(['random_spikes', 'waveforms', 'templates'])
new_analyzer= si.load_sorting_analyzer(folder='./test')
new_analyzer.select_units(unit_ids=[1])
```
Stack trace
```
Cell In[16], line 1
    new_analyzer.select_units(unit_ids=[1])
  File ~\Documents\GitHub\spikeinterface\src\spikeinterface\core\sortinganalyzer.py:714 in select_units
    return self._save_or_select(format=format, folder=folder, unit_ids=unit_ids)
  File ~\Documents\GitHub\spikeinterface\src\spikeinterface\core\sortinganalyzer.py:669 in _save_or_select
    new_ext = new_sorting_analyzer.extensions[extension_name] = extension.copy(
  File ~\Documents\GitHub\spikeinterface\src\spikeinterface\core\sortinganalyzer.py:1630 in copy
    new_extension.data = self._select_extension_data(unit_ids)
  File ~\Documents\GitHub\spikeinterface\src\spikeinterface\core\analyzer_extension_core.py:426 in _select_extension_data
    new_data[key] = arr[keep_unit_indices, :, :]
TypeError: unhashable type: 'numpy.ndarray'
```

[HIDDEN]

## Solution

[HIDDEN] I'm just not sure where we need to move it to? @alejoe91 @samuelgarcia.

cc @HerrietHsieh

### Additional contract requirements

- After reloading a `binary_folder` SortingAnalyzer with computed extensions, calling `select_units(unit_ids=[1])` must succeed and return an analyzer containing the requested unit.

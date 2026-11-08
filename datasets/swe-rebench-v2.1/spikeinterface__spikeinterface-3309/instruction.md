curation_dict from sortingview doesn't have 'mergeGroups' key
Hello,
I just updated Spikeinterface from 0.100.2 to 0.101.0 and am making the transition to using sorting analyzer class which has been pretty smooth for the most part but I'm getting an error related to sortingview_curation.
Here's my code:

```
save_folder = Path(data_folder) / "batch_sort"
analyzer = si.load_sorting_analyzer(
    folder=save_folder / "stage1/stage1_analyzer.zarr")

analyzer.compute("random_spikes")
analyzer.compute("waveforms", ms_before=1.0, ms_after=2.0)
analyzer.compute("templates")
analyzer.compute("template_similarity")
analyzer.compute("correlograms")
analyzer.compute("spike_amplitudes")
analyzer.compute("unit_locations")

si.plot_sorting_summary(analyzer, curation=True, backend="sortingview")
uri = input("\nPlease enter uri: ")
manual_curation_sorting = si.apply_sortingview_curation(
    analyzer.sorting, uri_or_json=uri)
```
However, apply_sortingview_curation throws me a KeyValue error.

```
si.apply_sortingview_curation(
    analyzer.sorting, uri_or_json=uri)
Traceback (most recent call last):

  Cell In[59], line 1
    si.apply_sortingview_curation(

  File ~\anaconda3\envs\si_env3\Lib\site-packages\spikeinterface\curation\sortingview_curation.py:74 in apply_sortingview_curation
    curation_dict = convert_from_sortingview_curation_format_v0(curation_dict)

  File ~\anaconda3\envs\si_env3\Lib\site-packages\spikeinterface\curation\curation_format.py:96 in convert_from_sortingview_curation_format_v0
    [HIDDEN]

KeyError: 'mergeGroups'
```

Printing sortingview_dict returns this:
```
{'labelsByUnit': {'12': ['reject'], '13': ['accept'], '14': ['accept'], '15': ['accept'], '16': ['accept'], '17': ['accept'], '22': ['accept'], '23': ['accept'], '24': ['accept'], '25': ['reject'], '26': ['accept'], '30': ['accept'], '31': ['accept'], '32': ['accept'], '37': ['accept'], '40': ['accept'], '41': ['accept'], '48': ['accept'], '49': ['accept'], '50': ['accept'], '51': ['accept'], '52': ['accept'], '54': ['reject'], '55': ['accept'], '56': ['accept'], '57': ['accept'], '58': ['accept'], '59': ['accept'], '67': ['accept'], '68': ['accept'], '69': ['reject'], '7': ['accept'], '72': ['reject'], '76': ['accept'], '77': ['accept']}}
```
The curation dict is returned from kcl.load_json function from sortingview_curation.py:
```
# download
if Path(uri_or_json).suffix == ".json" and not str(uri_or_json).startswith("gh://"):
    with open(uri_or_json, "r") as f:
        curation_dict = json.load(f)
else:
    try:
        import kachery_cloud as kcl
    except ImportError:
        raise ImportError(
            "To apply a SortingView manual curation, you need to have sortingview installed: "
            ">>> pip install sortingview"
        )

    try:
        curation_dict = kcl.load_json(uri=uri_or_json)
    except:
        raise Exception(f"Could not retrieve curation from SortingView uri: {uri_or_json}")

# convert to new format
if "format_version" not in curation_dict:
    curation_dict = convert_from_sortingview_curation_format_v0(curation_dict)
```

Is there a reason why kcl.load_json isn't returning a curation_dict with the correct format?

Also, thank you guys for doing a great job with SpikeInterface. It's been a pleasure working with it.

### Additional contract requirements

- A legacy SortingView curation without `mergeGroups` must be accepted as a curation with no merge operations.
- When such a curation assigns labels to units, applying it must retain those labels on the corresponding units in the returned sorting.

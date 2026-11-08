Storing channel index from MDA sorting in MdaSortingExtractor for downstream use
I am using spikeinterface and NeuroConv to convert a firings.mda sorting file from an older version of MountainSort to an NWB file. Currently this creates an NWB Units table with spike times and unit labels from MountainSort, but the table lacks information about which channel a unit was maximally detected on, which is available in the MDA file. NWB has an "electrodes" column in the Units table to store that.

[HIDDEN]

In the MDA files that I have, for each unit, every spike assigned to that unit has the same max channel index. Is that always the case, @magland?

[HIDDEN], so that downstream tools, e.g., NeuroConv, can use that information, e.g., when writing the sorting to an NWB file.

Does that sound reasonable? I am not an expert in spikeinterface and neuroconv. If there is a better approach, please let me know. Thanks!

Reference for firings.mda file format: https://mountainsort.readthedocs.io/en/latest/first_sort.html#format-of-the-firings-mda

### Additional contract requirements

- The per-spike maximum-channel information in the first row of the MDA `firings.mda` file must be publicly accessible after loading. `MdaSortingExtractor` exposes it as a unit property named `max_channel`: `MdaSortingExtractor.get_property("max_channel")` returns one value per unit, in unit order. When all spikes assigned to a unit have the same maximum-channel index, that value is the unit's common index, 1-indexed as in the MDA format. The MDA format stores a value per spike and does not guarantee that values agree within a unit; behavior for units with differing values is outside this contract.
- `MdaSortingExtractor.write_sorting(sorting, save_path, write_primary_channels=False)` is a static method. When `write_primary_channels=True`, the written `firings.mda` first row contains, for every spike, the `max_channel` value of the unit that spike belongs to.

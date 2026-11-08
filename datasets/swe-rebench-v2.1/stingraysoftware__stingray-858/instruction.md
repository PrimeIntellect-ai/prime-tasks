apply_gti_lists returns same result multiple times if input is a single GTI
### Description of the Bug

As follows

### Steps/Code to Replicate the Bug

The following unit test fails:
```
    reader = FITSTimeseriesReader(fname, output_class=EventList)

    evs = list(reader.apply_gti_lists([
            [[80000000, 80001024]]
    ]))
    assert len(evs) == 1
```

### Expected Results

The list should have length of 1

### Actual Results

The event lists returned are actually two, despite giving a single gti list

### Additional contract requirements

- Empty GTI lists must be skipped; `apply_gti_lists` must not yield an event list for an empty GTI list.

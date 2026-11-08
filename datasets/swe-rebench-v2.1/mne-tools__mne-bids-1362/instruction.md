get_entity_vals should ignore sidecars
### Describe the problem

My use case for `get_entity_vals` is this: for a given subject + task, find which sessions exist where the subject performed that task. This is proving to be quite hard (impossible?) to do with `get_entity_vals`, because `get_entity_vals` doesn't seem to discriminate when it comes to data files vs sidecars. MWE:

```py
from pathlib import Path
from tempfile import TemporaryDirectory

import mne_bids as mb

# create temporary fake BIDS dataset
with TemporaryDirectory() as root:
    root = Path(root)
    subdir = root / "sub-1" / "ses-a" / "meg"
    subdir.mkdir(parents=True)
    stem = "sub-1_ses-a_{}"
    for fname in ("task-IDS_meg.fif", "coordsystem.json"):
        (subdir / stem.format(fname)).touch()
    (subdir.parent / stem.format("scans.tsv")).touch()

    mb.print_dir_tree(root)

    # which of sub-1's session(s) have data for tasks other than IDS?
    result = mb.get_entity_vals(
        root / "sub-1",
        entity_key="session",
        ignore_tasks=("IDS",),
    )
print(result)
```

Result is this:
```
|tmp39vnjgza/
|--- sub-1/
|------ ses-a/
|--------- sub-1_ses-a_scans.tsv   # <-- false positive?
|--------- meg/
|------------ sub-1_ses-a_coordsystem.json   # <-- false positive?
|------------ sub-1_ses-a_task-IDS_meg.fif   # this is ignored by `ignore_tasks`
['a']
```

Expected (or at least desired) result here is that `get_entity_vals` returns `[]` because there are no *data files* once `ignore_tasks` has taken effect. I don't care if there are `coordsystem` or `scans` files present, because they relate to task(s) that I'm ignoring.

### Describe your solution

`get_entity_vals` should (have a param that lets you easily) ignore non-data sidecars.  I'm not super clear on what the ramifications of that would be, exactly which sidecars should be ignored, or how widely used `get_entity_vals` is internally or in user code. But at least the use cases I've thought about, I can't see why non-data files would be of interest --- in theory they'll only be present if data files are *also* present, and the spirit of the params like `ignore_tasks`, `ignore_sessions` etc seems to suggest that (one of) the intended uses of this function is to check whether a given task is present for a given subject, or check which subjects have task IDS in session a, or similar such queries.

### Describe possible alternatives

Maybe there's a better way to do what I want than `get_entity_vals`, that I'm not thinking of?

### Additional context

_No response_

### Additional contract requirements

The public `get_entity_vals` function provides an optional `ignore_suffixes` argument so callers can exclude non-data sidecar files from the files used to collect entity values. This filtering composes with the other filters: entity values present in matching data files that remain after filtering must still be returned.

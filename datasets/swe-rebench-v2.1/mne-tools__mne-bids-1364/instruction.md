ENH/BUG? : Allow empty-room matching of `task-noise` files in same session
### Describe the problem

Currently  MNE-BIDS' [`path._find_empty_room_candidates`](https://github.com/mne-tools/mne-bids/blob/46f284bf899e793a8a23a46c42c9ede09b900612/mne_bids/path.py#L42) will only look for files that use the `emptyroom` subject ID.

The [BIDS specification suggests that two possible routes to tagging empty-room recordings are possible](https://bids-specification.readthedocs.io/en/stable/modality-specific-files/magnetoencephalography.html#empty-room-meg-recordings):

1.  The subject is set to `emptyroom`, as implemented in MNE-BIDS, and the empty-room recordings are date-tagged using the session identifier.
2. The task is set to `noise` but otherwise the subject and session identities are preserved. The empty-room recording lives in the same folder as the rest of the subject data.

I may be missing another associated part of the code, but case 2 will not be recognized if the [`AssociatedEmptyRoom` field in the JSON sidecar is empty](https://bids-specification.readthedocs.io/en/stable/glossary.html#associatedemptyroom-metadata) for the path using the empty-room candidates function.

### Describe your solution

The underlying search logic for empty-room candidates should also look for `task-noise`  files in the same directory as part of generating candidates. Whether these are date-matched is up to the dev team, but it would be really nice to have these files recognized.

### Describe possible alternatives

If the feature isn't desirable to implement, it would be good to at least emit a warning that these files will not be used if they exist, or otherwise let the user know that only example 1 from the BIDS specification is being implemented.

### Additional context

_No response_

### Additional contract requirements

- When a `task-noise` recording located in the same directory as the experimental recording is the only empty-room candidate, `BIDSPath.find_empty_room()` returns that recording.
- - Calling `BIDSPath.find_empty_room()` when the path has no root raises a `ValueError` whose message contains `The root of the`.

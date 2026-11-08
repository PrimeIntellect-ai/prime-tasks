Support attaching previously uploaded photos to an observation by photo ID
This is useful for associating a single photo with multiple observations.

See this thread for details: https://forum.inaturalist.org/t/is-it-possible-to-use-the-api-to-attach-an-existing-photo-record-to-an-observation

### Additional contract requirements

- A previously uploaded photo can be associated with multiple observations.
- `create_observation` accepts photo IDs for previously uploaded photos without including `photo_ids` in the observation creation request.
- When `update_observation` receives photo IDs, it includes them together with the observation's existing photo IDs in `local_photos`, keyed by the observation ID as a string; photo-ID order is not significant. Setting `ignore_photos=False` omits the automatic `ignore_photos=1` request flag.
- `upload` accepts photo IDs to associate previously uploaded photos with the specified observation and returns a list containing the response of each upload operation.

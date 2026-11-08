Segment Efforts client method uses undocumented API endpoint
There are currently two client methods:

- `get_segment_efforts()`
- `get_segment_effort()`

The first uses an undocumented endpoint `/segments/{segment_id}/all_efforts`. Both should use the documented/supported Strava API endpoint `/segment_efforts`; see https://developers.strava.com/docs/reference/#api-SegmentEfforts.

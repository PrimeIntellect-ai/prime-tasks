Curator delete crashes if encountering an old timestamp
### Expected Behavior
Curator delete should not crash when trying to clean up indices

### Actual Behavior
Curator starts up and exits before any indices has been cleaned up with this error `Unusually formatted epoch timestamp. Should be 10, 13, or more digits`

We are running a curator job that runs this filter to look for old indices
```
- filtertype: age
      source: field_stats
      direction: older
      unit: days
      unit_count: 14
      field: '@timestamp'
      stats_result: max_value
```
However some host was started with an incorrect timestamp (year 1988), creating documents with a 12 digit timestamp, which was then set as the min_value for the index field_stats.

### Specifications

  - Version: ES 5.6.6, Curator 5.5.4

## Context (Environment)
We do index rollovers and deletions of indices older than 14 days. When a host sent in some docs with a very old timestamp from year 1988, Curator would crash complaining about a 12 digit timestamp, causing no indices to be deleted. With no old indices deleted we started growing in disk usage. Once the bad host was fixed, we tried to exclude the two indices we got with 12 digit timestamps but [HIDDEN] so exclude did not work.

## Detailed Description
I don't have the context for why 12 digit timestamps are not allowed in the first place, but I have created a code fix to allow it.

### Additional contract requirements

- Age filtering must treat a 12-digit Unix epoch timestamp as valid and must not abort when an index contains one; it should continue its normal age-based selection.

Add migration for change in summaries properties
https://github.com/radiantearth/stac-spec/pull/967

Summaries changed from min/max to minimum/maximum. Previous to #309 we were not parsing out the stats object stats object explicitly, and that PR adds a RangeSummary object with a minimum and maximum correctly named, so we only need to add functionality to migrate summary objects.

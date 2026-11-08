Make stats publish interval configurable
The statistician publish interval is currently fixed at 3s in each component.

### Additional contract requirements

The publishing interval is configurable with the `stats_interval` configuration option, represented by `Config.StatsInterval`. The listener, filter, and writer components must publish statistics according to this interval. When it is not configured, the publishing interval remains 3 seconds.

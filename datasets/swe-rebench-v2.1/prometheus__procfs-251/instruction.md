Implement parsing of /proc/loadavg
Looks like "/proc/loadavg" file isn't parsed at now.
It's useful from this to get current system load.

### Additional contract requirements

Callers can retrieve the one-, five-, and fifteen-minute load averages with `FS.LoadAvg()`. The returned values are available in the `Load1`, `Load5`, and `Load15` fields, respectively.

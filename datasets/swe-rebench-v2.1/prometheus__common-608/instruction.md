OpenMetrics: _total suffix repeated multiple times
### Description

Today we faced the problem with counter export in openmetrics format: counter names keep being appended by "_total" suffices, one time for every new labelset.

This is how it looks in grafana metric browser after being collected by prometheus

<img width="1154" alt="Screenshot" src="https://github.com/prometheus/common/assets/11293374/4fcc1f3b-83d0-4c5f-86aa-3a05da0886c6">

### Debug

[HIDDEN]

and was introduced in [this commit](https://github.com/prometheus/common/pull/544/commits/6a86956d41af916f0c048f4988d93994bb865b9e).

### Affected versions

github.com/prometheus/common v0.50.0

### Additional contract requirements

- In OpenMetrics counter export, adding labelsets must not cause the counter name to accumulate additional `_total` suffixes. All labelsets in the same counter family must use a consistent counter name, with the suffix appearing at most once.

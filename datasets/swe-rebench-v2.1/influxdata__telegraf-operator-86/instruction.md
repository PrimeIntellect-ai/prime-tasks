Allow removing resource requests/limits on sidecar
In my case I'd like to remove the CPU resource limit on the telegraf sidecar. If I leave out the annotation, it will use the default value. It would be nice if there are either 1) no resource requests/limits on the sidecar, or 2) a way to disable setting a default value

### Additional contract requirements

- When the `telegraf.influxdata.com/requests-cpu`, `telegraf.influxdata.com/requests-memory`, `telegraf.influxdata.com/limits-cpu`, and `telegraf.influxdata.com/limits-memory` annotations are all set to the empty string (`""`), the injected Telegraf container must have `resources: {}`. Validation must accept empty resource values.

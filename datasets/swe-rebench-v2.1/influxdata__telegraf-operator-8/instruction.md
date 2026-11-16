Support `telegraf.influxdata.com/port` annotation
It's would be cool to support `telegraf.influxdata.com/port` in addition to `telegraf.influxdata.com/ports`

### Additional contract requirements

If both annotations are present, the resulting Telegraf scrape configuration must include the ports from both annotations, with a port specified in both included only once.

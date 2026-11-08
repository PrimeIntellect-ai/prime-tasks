Java client: SHOW SERIES return empty result
Hi,
During implementation of tool that needs to retrieve schema of InfluxDB 2.7, I have encountered issue where `show series` return empty result, although underlying CSV contains correct data.

Data retrieved underneath as CSV is in format (note that two columns are empty!):
```
name,tags,key
,,temperature
,,pressure
```

I believe issue is in line https://github.com/influxdata/influxdb-client-java/blob/master/client/src/main/java/com/influxdb/client/internal/InfluxQLQueryApiImpl.java#L129 where last line of CSV is detected incorrectly, and [HIDDEN]

__Steps to reproduce:__

1. Run `InfluxQLQueryResult result = client.getInfluxQLQueryApi().query(new InfluxQLQuery("SHOW SERIES", "mydb"));`
2. Observe that `result.getResults().size() == 1`, but `result.getResults().get(0).getSeries().size() == 0`

__Expected behavior:__
Object `InfluxQLQueryResult` should contain list of series retrieved from InfluxDB, as running `SHOW SERIES` from command line does it.

__Actual behavior:__
Describe What actually happened.

__Specifications:__
 - Client Version: 7.0.0
 - InfluxDB Version: 2.7.0
 - JDK Version: openjdk version "17.0.8.1" 2023-08-24
 - Platform: Linux (Arch)

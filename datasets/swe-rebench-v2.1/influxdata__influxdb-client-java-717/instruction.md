How to use Flux(v6.9.0) to filter through fuzzy(Imprecise) queries(regular expression)?
__Proposal:__
Filter fuzzy(Imprecise) queries by tag or field.

__Current behavior:__
Finding that there is no imprecise filtering query method or regular expression filtering method, I tried using custom but he doesn't work as expected.

```
Flux flux = Flux
            .from("basic")
            .range(Instant.now(), Instant.now())
            .filter(Restrictions.and(
                    Restrictions.measurement().equal("api_log"),
                    Restrictions.tag("org_id").equal("EDUCLOUD"),
                    Restrictions.tag("title").custom("/account/", "=~"))
            .pivot(List.of("_time"), List.of("_field"), "_value")
            .group()
            .sort(List.of("_time"), true)
            .limit(10, (0 - 1) * 10);
```

anticipate:
```
from(bucket:"basic")
	|> range(start:2023-07-14T15:59:59.000000000Z, stop:2023-07-14T15:59:59.000000000Z)
	|> filter(fn: (r) => (r["_measurement"] == "api_log" and r["orgId"] == "EDUCLOUD" and r["title"] =~ /account/))
	|> pivot(rowKey:["_time"], columnKey:["_field"], valueColumn:"_value")
	|> group()
	|> sort(columns:["_time"], desc:true)
	|> limit(n:10, offset:0)
```
actual:
```
from(bucket:"basic")
	|> range(start:2023-07-14T15:59:59.000000000Z, stop:2023-07-14T15:59:59.000000000Z)
	|> filter(fn: (r) => (r["_measurement"] == "api_log" and r["orgId"] == "EDUCLOUD" and r["title"] =~ "/account/"))
	|> pivot(rowKey:["_time"], columnKey:["_field"], valueColumn:"_value")
	|> group()
	|> sort(columns:["_time"], desc:true)
	|> limit(n:10, offset:0)
```
error:
`com.influxdb.exceptions.InternalServerErrorException: HTTP status code: 500; Message: type error 3:88-3:109: string != regexp`
![image](https://github.com/influxdata/influxdb-client-java/assets/54580227/c6d72e4d-b298-4b2d-a4aa-689574dc5473)

__Desired behavior:__
Imprecise filter query method or regular expression filter method, custom filter regular expression is normal

__Alternatives considered:__
Restrictions.custom()  In the tank regular expression

__Use case:__
Regular expressions (regular expressions) are very powerful when matching patterns in large data collections, and they can effectively filter the amount of data.

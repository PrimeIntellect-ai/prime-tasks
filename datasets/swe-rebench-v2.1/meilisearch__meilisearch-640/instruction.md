Bug in filtering when using OR and grouping expressions with parentheses
Hi Meilisearch,

I found a bug when filtering using OR  while i am grouping expressions with parentheses.

When i have a OR in my options query it looks to that OR and not any more to the other AND filters.

See my screenshot with the query and the filters:

Search on: 'test'
Options: [filters] => "branche" = "32" AND ("gender" = "male" OR "gender" = "female")
)

Result found:
```
 Array
                (
                    [id] => 1
                    [firstname] => Test name
                    [middlename] =>
                    [lastname] => Lastname test
                    [gender] => female
                    [branche] => 39
)
```

Se the result above. Branche 39 shouldend be in the result.

**Edit:** It results all rows that have gender = 'female' but it does not result rows that are 'male'.

I also find out that it does not matter where my OR is. This bug is also shown when i put the OR in the begin of the query.

**Edit:** I am using the PHP client.

### Additional contract requirements

- Filter values may be decimal (floating-point) numbers, for example `vote_average > 8.0`. Such comparisons must be parsed and applied in the same way as integer comparisons.
- A successful search request returns HTTP status code `200`.

Add a TopHits aggregation
ES provides a Top Hits sub aggregation : https://www.elastic.co/guide/en/elasticsearch/reference/1.7/search-aggregations-metrics-top-hits-aggregation.html
https://github.com/elastic/elasticsearch/blob/master/docs/java-api/aggregations/metrics/tophits-aggregation.asciidoc

Using jest, we can query ES by using the AggregationBuilders.topHits() query builder, but there is no way to get the result since the TopHits aggregation type does not exist in Jest.
We can get the parent aggregation :
```
result.getAggregations().getTermsAggregation("label.raw").getBuckets()
```
But once we have the bucket entry, we can not get the TopHits subaggregation.

### Additional contract requirements

Expose a public `TopHitsAggregation` result type and a `TermsAggregation.Entry.getTopHitsAggregation(String)` accessor that retrieves a named top-hits subaggregation from a terms bucket. The returned result must let callers obtain the source documents for its hits as JSON strings through `getSourceAsStringList()`.

add additionalTableAttributes to `TableRetriever#retrieveTablesFromDataDictionary`
### Feature Request

When using `retrieveTablesFromDataDictionary`, `schemacrawler.crawl.MetadataResultSet#getAttributes` are not set into table attributes.

If I want additional attributes, I would have to define another `ADDITIONAL_TABLE_ATTRIBUTES` query. In my case, I can use one query to get the table info together with some additional attributes saving one additional `ADDITIONAL_TABLE_ATTRIBUTES` query.

### Possible Alternatives

_No response_

### Additional Context

_No response_

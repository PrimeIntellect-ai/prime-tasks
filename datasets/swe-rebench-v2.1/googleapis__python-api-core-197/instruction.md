The page_iterator API proble, and proposed fix
It looks to me like the [page_iterator](https://github.com/googleapis/python-api-core/blob/f2600cce8bc8eaf24c2461908cfb5a2e9b489296/google/api_core/page_iterator.py) API has a problem.

The `Iterator` class provides pagination, and yet invites clients to do their own pagination by taking a page token.  (The documentation for `page_token` in the BigQuery [list_tables](https://googleapis.dev/python/bigquery/latest/generated/google.cloud.bigquery.client.Client.html?highlight=list_tables#google.cloud.bigquery.client.Client.list_tables) method specifically says this.)  I would hope that this isn't the intent.

Empirically, the default pagination for `list_tables` is 50 rows per page, [which is arguably too low](https://github.com/googleapis/python-bigquery-sqlalchemy/issues/173), causing many REST API calls if there are many tables in a dataset.  If you pass a largish number for `max_results`, then the page size increases to 1000 rows, but no more than 1000 and you get no more than that many results.  Using `max_results` to influence the page size forces the client of `page_iterator` to do its own pagination if there is any chance of total number of items exceeding the maximum `max_results`, which for `list_tables` is 2147483647.  Arguably, a dataset wouldn't have more than that many tables, but this interface  is also used for [list_rows](https://googleapis.dev/python/bigquery/latest/generated/google.cloud.bigquery.client.Client.html?highlight=list_rows#google.cloud.bigquery.client.Client.list_rows), which also limits `max_results` to 2147483647.  One wouldn't want to limit table rows to 2147483647 just to affect the pagination, although empirically, `max_results` doesn't affect pagination in the case of `list_rows`.

A straightforward way to address this would be to add a `page_size` argument to the iterator. Of course, to get the benefit, the option would need to be added to higher-level libraries.

**I'd be happy to create a PR to add this argument.**

BTW, it's weird to take `page_token`.  Is this a holdover from an earlier design? Should it be deprecated?

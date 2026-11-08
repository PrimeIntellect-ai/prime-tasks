Add "count" functionality
There are times I want to get the total count of list data, without actually needing the dataset. This is particularly handy with filtered lists. [HIDDEN]

But there's no way to do this in pynetbox currently. I envision some sort of API like this:

```
>>> t1_circuits_count = nb.circuits.circuits.count(type_id=2)

>>> print(t1_circuits_count)
12
```

And behind the scenes it's just getting back a single item response, but still has the `count` key. This way I could get total circuits for each circuit type very quickly, without having to pull down a dataset of thousands of rows (and far more database queries).

### Additional contract requirements

- Add a public method `Endpoint.count(*args, **kwargs)` on `pynetbox.core.endpoint.Endpoint` that returns an `int`: the total number of objects matching the supplied filters, or the total number of objects on the endpoint when no arguments are given. A single positional argument is used as a free-form search string. Keyword arguments are used as endpoint filters. Reserved keyword arguments (`id`, `pk`, `limit`, `offset`) raise `ValueError`.
- Add a public method `Request.get_count()` on `pynetbox.core.query.Request` that returns an `int`: the `count` value from the API response for the query. It raises `RequestError` if the HTTP request fails and `ContentError` if the response is not valid JSON.
- A count request must obtain the total count without downloading the full result dataset. The response used for counting must contain at most one result item while retaining the total `count` value.

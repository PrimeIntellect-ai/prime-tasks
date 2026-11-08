Querying a view with a boolean type key raises a CloudantArgumentError
## Bug Description

### 1. Steps to reproduce and the simplest code sample possible to demonstrate the issue

Create a cloudant database view, and attempt to query the view using the python-cloudant library as follows:
```
results = database.get_view_result('_design/doc', 'view-name', raw_result=True, key=False)
```
The above code will raise a CloudantArgumentError due to the validation on this line https://github.com/cloudant/python-cloudant/blob/33781463ff85c8bb535bd6ede2049e4d3bec6c4c/src/cloudant/_common_util.py#L192

### 2. What you expected to happen

The expected outcome would be that the view get filtered by the boolean type key instead of raising the error

I removed the validation locally and reinitiated the view query, and the key filtered fine from the CouchDB library end i.e. their library accepted a boolean type for the key argument

### 3. What actually happened

A CloudantArgumentError was raised when trying to filter by a boolean value for the argument key

## Environment details
<!--
- Version(s) that are affected by this issue.
    > 2.0.2
- Python version
    > 3.6.2
-->

Python 3.9.2
Database server: IBM Cloudant

### Additional contract requirements

- The view query parameter translation helper `python_to_couch(params)` in module `cloudant._common_util` accepts a boolean value for the `key`, `startkey`, and `endkey` parameters and translates it to the JSON string literal `"true"` or `"false"`.
- Boolean values remain invalid for view parameters that accept only integers (for example `limit` and `skip`); supplying one must still raise `CloudantArgumentError`.

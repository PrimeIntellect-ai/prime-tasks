Use version.py instead of pkg_resource
I met the same issue on the google-api-python-client about the pkg_resources exception (
https://github.com/googleapis/python-api-core/issues/27)
https://github.com/googleapis/google-api-python-client/blob/0f2e2a13bf8f4e4150fed1f79cf995309ddc34f1/googleapiclient/model.py#L34

```
pkg_resources.DistributionNotFound: The 'google-api-python-client' distribution was not found and is required by the application
```

I found the google-auth source and python-api-core has changed. Could it be changed this way accordingly?
https://github.com/googleapis/google-auth-library-python/pull/683/commits/ff6b52ccbb3811dbc5adcb2c12f6d66fa4e8ef78

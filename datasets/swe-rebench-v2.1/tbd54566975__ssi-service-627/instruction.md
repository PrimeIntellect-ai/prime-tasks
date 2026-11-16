The pageSize and pageToken parameters are perhaps not working when calling the ListSubmissions function.
I found that when calling

http://localhost:3000/v1/presentations/submissions?pageSize=1&filter=status="approved"
the filter parameter is effective, but the pageSize parameter is not.

Furthermore, I found that

`pageSizeStr := framework.GetParam(c, *PageSizeParam*)`

and

`queryPageToken := framework.GetParam(c, *PageTokenParam*)`

in the `ParsePaginationParams` function both return nil.

I modified them to

[HIDDEN]

and

[HIDDEN]

and it seems to work correctly in terms of the number of results returned. Considering that both functions `ListDIDsByMethod` and `ListSubmissions` that call `ParsePaginationParams` are GET methods, [HIDDEN]

### Additional contract requirements

- For the GET listing operations `ListDIDsByMethod` and `ListSubmissions`, `pageSize` and `pageToken` supplied in the request URL must be honored when determining the returned page.
- The pagination parsing function `ParsePaginationQueryValues` (see interface.md) must respond with HTTP status 400 and an error body that contains the following exact messages:
  - when `pageSize` is present but not greater than 0: the body contains `'pageSize' must be greater than 0`
  - when `pageToken` cannot be decoded: the body contains `token value cannot be decoded`
  - when the query encoded in `pageToken` does not match the request query: the body contains `page token must be for the same query`

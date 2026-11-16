Change GET PUT POST DELETE requests format for collections
### I'm submitting a
[x] bug report.

### Current Behaviour:
As discussed in the confcall, the current API semantics for operations on collections is far from being conventional:
```
/serverapi/MovieCollection/4f61070a-f647-4a65-9b0a-cbab4bcf0510/delete/3e1462f8-93ad-4a52-a371-a6fd5724c904, 1f6f1df8-788d-430a-8398-2e3302407fc0
```
Two major points:
* there is the repetition of "delete" in the uri
* multiple ids are listed with commas in the path

### Expected Behaviour:
The correct semantics should be
```
DELETE /serverapi/MovieCollection/4f61070a-f647-4a65-9b0a-cbab4bcf0510/?instances=3e1462f8-93ad-4a52-a371-a6fd5724c904,1f6f1df8-788d-430a-8398-2e3302407fc0
```
The operation method should be only defined in the request method and the list of ids to delete should be defined in a proper `instances` parameter. Every HTTP method can accept URL parameters (including PUT and DELETE).

### Additional contract requirements

- Collection-member GET requests should identify the requested member with an `instances` query parameter on the collection URI (for example, `GET <collection-URI>?instances=<member-id>`), rather than a member-ID path segment.
- When collection PUT requests provide object IDs, pass them in an `instances` query parameter on the collection URI (for example, `PUT <collection-URI>?instances=<ids>`), rather than in an ID-bearing path segment.

TAXIICollectionSource.query() only returns the first page
I noticed that the TAXIICollectionSource methods query(), relationships(), ... only operates with the first page returned by the associated TAXII 2.0 server.

I did tests with a local Medallion server v1.1.0 which have a default max_page_size of 100.

By calling TAXIICollectionSource.query() I can get only 100/10000 objects. Also, when calling relationships(stix2_id) the results are limited to those 100 objects.

The only solution I found is increasing that max_page_size, so all objects are returned in one call.

### Additional contract requirements

- `taxii2client.v20.Collection.get_objects(accept=MEDIA_TYPE_STIX_V20, start=0, per_request=0, **filter_kwargs)` returns a `requests.Response` on success (HTTP status 200) whose `Content-Range` header reports the returned page and whose body is a serialized STIX Bundle.
- `taxii2client.v21.Collection.get_objects(**filter_kwargs)` returns a mapping containing an `objects` list and a `more` boolean that is true when further pages are available.

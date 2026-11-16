Links under top-level 'links' may be objects
I am trying to validate COD implementation (in development) using `optimade-python-tools` v0.9.8. The validator seems to require the values under the top-level `links` being strings:
```
$ optimade_validator https://www.crystallography.net/cod-test/optimade -v 5
Testing entire implementation at https://www.crystallography.net/cod-test/optimade...

Mandatory tests:
[snip]
2020-07-10 14:51:48,137 - optimade.validator.validator |    DEBUG: Testing multiple entry endpoint of references
✔: https://www.crystallography.net/cod-test/optimade/references?page_limit=5 - request successful.
✖: https://www.crystallography.net/cod-test/optimade/references?page_limit=5 - deserialize_response - failed with error
[snip]
	links -> first
	  str type expected (type=type_error.str)
	links -> next
	  str type expected (type=type_error.str)
Traceback (most recent call last):
[snip]
  File "/home/andrius/.local/lib/python3.6/site-packages/optimade/validator/validator.py", line 619, in get_endpoint
    request_str = request_str.replace("\n", "")
AttributeError: 'dict' object has no attribute 'replace'
```
In the COD implementation these values are "link objects", as per OPTIMADE specification:
```json
   "links" : {
      "first" : {
         "href" : "http://www.crystallography.net/cod-test/optimade/v1.0.0/references?page_limit=5"
      },
      "next" : {
         "href" : "http://www.crystallography.net/cod-test/optimade/v1.0.0/references?page_limit=5&page_offset=5"
      },
      "base_url" : "http://www.crystallography.net/cod-test/optimade/v1.0.0/"
   }
```

### Additional contract requirements

For the standard pagination links (`first`, `last`, `prev`, and `next`), accept either a URL string or a link object. A link object must have an `href` containing a valid URL; malformed objects are rejected.

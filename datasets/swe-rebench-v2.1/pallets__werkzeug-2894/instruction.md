Some relative redirect strings incorrectly bypass iri_to_uri normalization.
## Summary
It appears logic introduced in https://github.com/pallets/werkzeug/pull/2695 to work-around the `itms-services:` schema oddity has an overly broad assumption that is results in invalid URIs due to not percent-encoding relative IRIs as intended.

Ultimately, this can trick browsers into behaving badly when faced with invalid relative URL locations. But I think it is ours to fix in werkzeug because the current code is emitting an invalid location header per RFCs (and the presumed intention of the code.)

RFC 3986 for URIs has a [section 2](https://datatracker.ietf.org/doc/html/rfc3986#section-2.3) that essentially says URI components should be percent-encoded if they aren't part of the "reserved" or explicitly "unreserved" lists of characters. As an case-study: backslashes should be percent-encoded. Indeed, werkzeug seems to intent to encode them, but this issue describes the case where the typical encoding logic is not being applied.

## Replication
As an example consider an app expecting to use `redirect(relative_uri)` and expecting werkzeug to properly encode the `Location:` header (as it historically would before the mentioned work-around)

```python
from werkzeug.utils import redirect
problem_relative_uri = '/\\\\github.com?extra=data&blank=#fragment'
response = redirect(problem_relative_uri)
response.location
# '/\\\\github.com?extra=data&blank=#fragment'
```

Note the backslashes (`\`) in this URI are /not/ being encoded as `%5C` .

As a smaller test case:
```python
from werkzeug.urls import iri_to_uri, _invalid_iri_to_uri
problem_relative_uri = '/\\\\github.com?extra=data&blank=#fragment'
_invalid_iri_to_uri(problem_relative_uri)
# '/\\\\github.com?extra=data&blank=#fragment'
# :-(
```
## Expected Behavior
The previous encoding behavior before the wrapper was desirable
```python
iri_to_uri(problem_relative_uri)
# '/%5C%5Cgithub.com?extra=data&blank=#fragment'
# :-)
```

Environment:

- Python version: 3.12.1
- Werkzeug version: 3.0.1


## Relevant Code
https://github.com/pallets/werkzeug/blob/d3dd65a27388fbd39d146caacf2563639ba622f0/src/werkzeug/wrappers/response.py#L482-L483

https://github.com/pallets/werkzeug/blob/d3dd65a27388fbd39d146caacf2563639ba622f0/src/werkzeug/urls.py#L167-L185

### Additional contract requirements

- `werkzeug.urls.iri_to_uri(iri: str) -> str` returns a normalized URI, percent-encoding characters outside the standard reserved and unreserved sets. For the `itms-services` scheme, the `//` component is preserved.
- A relative redirect target containing backslashes must produce a `Location` header with those backslashes percent-encoded while preserving the relative form and query delimiter. For example, `/\\test.example?q` produces `/%5C%5Ctest.example?q`.

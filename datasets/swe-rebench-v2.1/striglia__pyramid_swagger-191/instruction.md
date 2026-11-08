Be more precise with which 4xx error is raised
Validation currently raises HTTP 400s when 1) a route is not matched in the spec and 2) a route is matched but validation fails. This is better than nothing, but not quite semantically correct.

The missing route should definitely return a 404, and the failed validation can return either 400 or 422 (see http://www.bennadel.com/blog/2434-http-status-codes-for-invalid-data-400-vs-422.htm for details).

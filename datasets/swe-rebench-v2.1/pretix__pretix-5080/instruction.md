Updating meta_data isn't reflected in response
### Problem and impact

When updating the meta_data via api I expect the response to reflect the newly updated values.

e.g.: PATCH /events/test-id/
{"meta: {"test": "hello-1"}}
Response:
{"meta: {"test": "hello-1"}}

### Expected behaviour

I don't receive the new values, but get the old ones:

 PATCH /events/test-id/
{"meta: {"test": "hello-new"}}
Response:
{"meta: {"test": "hello-old"}}

### Steps to reproduce

_No response_

### Screenshots

_No response_

### Link

_No response_

### Browser (software, desktop or mobile?) and version

_No response_

### Operating system, dependency versions

_No response_

### Version

_No response_

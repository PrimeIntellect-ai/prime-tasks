Add tests for PUT/DELETE request for multiple Class objects in test_app.py
### I'm submitting a
- [ ] bug report.
- [x] feature request.

### Current Behaviour:
<!-- Describe about the bug -->
Currently, we don’t have any tests for PUT/DELETE request for multiple Class objects in test_app.py.
We do have some tests in test_crud.py, but we’re directly using functions from crud.py to
test the behaviour and not making requests to the endpoints to check status codes.

### Expected Behaviour:
<!-- Describe what will happen if bug is removed -->
We can add some tests in test_app.py as well to improve test_coverage and test the functioning of routes using test_app_client and checking the correct status code for every response.
### Steps to reproduce:
<!-- If you can then please provide the steps to reproduce the bug -->

### Snapshot:
<!-- If you can then please provide the screenshot of the issue you are facing -->

### Environment:
<!-- Please provide the following environment details -->
* python version
* pip version
* OS details

### Do you want to work on this issue?
<!-- yes/no -->

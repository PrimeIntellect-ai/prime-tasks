Registration/Login form fields should not include "request"
**Describe the bug**

The request field is send in the registration/login form information.

**Expected behavior**

As the request ID is already included in the action url we should filter out this key from the form fields.

### Additional contract requirements

- Registration and login forms must also have method `POST`.

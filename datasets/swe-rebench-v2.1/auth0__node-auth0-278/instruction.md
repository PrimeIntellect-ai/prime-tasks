How to delete guardian multifactor?
I see that there is a method to delete a user's multifactor provider, but it seems that this only accepts "google-authenticator" or "duo" as an option (https://auth0.com/docs/api/management/v2#!/Users/delete_multifactor_by_provider). How can I clear a user's sms verification setup?


**None of the endpoints dealing with Guardian (get Guardian enrollments, delete enrollments) are implemented here.**

### Additional contract requirements

The ManagementClient must provide operations named `getGuardianEnrollment(params, cb)` and `deleteGuardianEnrollment(params, cb)` for individual Guardian enrollments. Each operation accepts an enrollment `id` in `params`. Retrieval returns the enrollment data; deletion removes the enrollment so that SMS verification setup can be cleared. Callers may use either a callback or, when no callback is supplied, a promise; retrieval returns the API response data and failures are reported through the callback or rejected promise.

Calling the loader after google API has failed with x retries should try loading the library again
Relates to #93  and #99

 **Is your feature request related to a problem? Please describe.**
Relates to #93
For a SPA this is useful as there is no page reload on navigation.

 **Describe the solution you'd like**
Similar to [this](https://github.com/googlemaps/js-api-loader/issues/93#issuecomment-727040227)

 **Describe alternatives you've considered**
N/A

 **Additional context**
N/A

### Additional contract requirements

A call made after a load attempt and all of its configured retries have failed starts a fresh load attempt rather than reusing the settled failure. Calls made while a load attempt or its retries are still in progress continue to await that active sequence; they do not start a new retry cycle.

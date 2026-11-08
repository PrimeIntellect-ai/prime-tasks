Dont deploy when webpack fails
If webpack has an error we should log it and stop what we're doing, this goes for builds and deploys.

### Additional contract requirements

- When webpack fails, the build or deploy must fail (the returned promise rejects) and must not continue to later steps.

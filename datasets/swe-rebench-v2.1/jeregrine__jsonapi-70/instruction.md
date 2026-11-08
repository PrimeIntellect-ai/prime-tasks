Hidden fields
@jeregrine curious to get your thoughts on whether this is a feature we want or something I should keep in my application.  There are a few instances in which we need to include a field in our view so it can be posted or patched but we don't want it included in the response (think passwords).  For this I've implemented a `hidden/0` that works like `fields/0` but is used to hide certain values from the response.

Is this something you'd be open to considering?  If so I'll open a PR.

### Additional contract requirements

A field hidden from response attributes must remain in the view's ordinary fields and remain available as input for posted or patched data. Hiding a field affects response output only.

Test for AvailableApiVersion is correct for the wrong reasons
Since the `root_validator` `crosscheck_url_and_version` has been added to the model `AvailableApiVersion`, the test `test_available_api_versions()` in `tests/models/test_models.py` succeeds for the wrong reasons.

[HIDDEN]

### Additional contract requirements

- Constructing `AvailableApiVersion` with a malformed or disallowed URL must fail with a validation error identifying the URL validation failure, such as `url MUST be a versioned base URL` or `URL scheme not permitted`.
- A URL and version that are individually valid but incompatible with each other must fail with a validation error containing `is not compatible with url version`.

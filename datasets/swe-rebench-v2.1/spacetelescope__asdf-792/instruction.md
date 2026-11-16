Add option to skip validation
Reasons for doing this will probably be related to performance. I'm inclined to say that skipping validation should result in a loud warning so that users do not get into the habit of doing this all the time.

### Additional contract requirements

The opt-out is available as the `validate_on_read` option on `asdf.open` and `AsdfInFits.open`. Validation remains enabled when this option is omitted; setting it to `False` skips read-time schema validation, while setting it to `True` enables validation.

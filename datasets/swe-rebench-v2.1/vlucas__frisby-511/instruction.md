False positives with body validation
I'm currently working on migrating an existing API to a new tech stack. As a part of that process I created a Frisby-based characterization test suite, and intend to test-drive the migration. However, tests are passing under two circumstances that seem incorrect to me:

- If the `Content-Type` is not `application/json`-ish (I'm using JSON:API), such as it's blank, the test passes with a `jsonTypesStrict` assertion.
- If the response body is _empty_ but contains an appropriate `Content-Type` header, the test passes with a `jsonTypesStrict` assertion.

Are these by design? If so, how can I guarantee these tests fail when the body is the incorrect type or missing?

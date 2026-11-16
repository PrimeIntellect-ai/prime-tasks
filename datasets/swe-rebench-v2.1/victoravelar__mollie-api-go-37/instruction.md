Implement Captures API resource
**Description**
Implement the API endpoints related to the captures resource and provide test coverage, as an example you might take a look at #6

**Additional context**
The API reference for refunds can be found here: https://docs.mollie.com/reference/v2/captures-api/get-capture

### Additional contract requirements

The client exposes the captures resource as a `Captures *CapturesService` field on `Client` (package `mollie`).

Captures resource (package `mollie`):
- `CapturesService.Get(pID string, cID string) (*Capture, error)` retrieves a single capture belonging to the specified payment.
- `CapturesService.List(pID string) (*CapturesList, error)` lists all captures associated with the specified payment.
- `Capture` has an `ID string` field.
- `CapturesList` has a `Count int` field and an `Embedded` struct field containing a `Captures []Capture` field.

The requests are made against these endpoints (relative to the API base URL):
- `v2/payments/{pID}/captures/{cID}` for `CapturesService.Get`.
- `v2/payments/{pID}/captures` for `CapturesService.List`.

For captures requests, errors returned for an HTTP error response must contain `Internal Server Error`, and errors returned for a malformed JSON response must contain `invalid character`.

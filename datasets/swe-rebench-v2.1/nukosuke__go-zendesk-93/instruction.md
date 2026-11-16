Add support for trigger
API reference: https://developer.zendesk.com/rest_api/docs/support/triggers

- [x] Create
- [x] Read
- [x] Update
- [x] Delete

### Additional contract requirements

- Add a public method `GetTrigger(id int64) (Trigger, error)` on `Client` in package `zendesk` that retrieves a single trigger by its ID and returns a non-nil error if the request fails or the response cannot be decoded.
- Add a public method `UpdateTrigger(id int64, trigger Trigger) (Trigger, error)` on `Client` in package `zendesk` that updates the specified trigger and returns the updated trigger, and returns a non-nil error if the request fails or the response cannot be decoded.
- Add a public method `DeleteTrigger(id int64) error` on `Client` in package `zendesk` that deletes the specified trigger and returns nil on success (HTTP 204) or a non-nil error otherwise.

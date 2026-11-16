Implement Scheduled Statuses API
Mastodon’s [Scheduled Statuses API](https://docs.joinmastodon.org/methods/scheduled_statuses) allows users to view, update, and cancel scheduled statuses.

The goal of this task is to implement the following endpoints of this API in BigBone:

* [View scheduled statuses](https://docs.joinmastodon.org/methods/scheduled_statuses/#get)
* [View a single scheduled status](https://docs.joinmastodon.org/methods/scheduled_statuses/#get-one)
* [Update a scheduled status’s publishing date](https://docs.joinmastodon.org/methods/scheduled_statuses/#update)
* [Cancel a scheduled status](https://docs.joinmastodon.org/methods/scheduled_statuses/#cancel)

The Scheduled Statuses API as documented by Mastodon can be found here:
[docs.joinmastodon.org/methods/scheduled_statuses](https://docs.joinmastodon.org/methods/scheduled_statuses/)

> [!TIP]
> A lot of other endpoints similar to this have already been implemented. In order to get an idea how to implement this, I suggest that you study the code upfront. Start with one of the `*Methods.kt` files.

---

Please consult the following documents to make sure your contribution meets our projects criteria:

[Code of Conduct](https://github.com/andregasser/bigbone/blob/master/CODE_OF_CONDUCT.md?rgh-link-date=2023-11-03T07%3A22%3A10Z)

[Code Contribution Guidelines](https://github.com/andregasser/bigbone/blob/master/CONTRIBUTING.md?rgh-link-date=2023-11-03T07%3A22%3A10Z)

### Additional contract requirements

- The Scheduled Statuses functionality is exposed through a class named `ScheduledStatusMethods` in the package `social.bigbone.api.method`, constructed from a `MastodonClient`, following the same conventions as the other `*Methods` classes.
- `getScheduledStatuses(range: Range = Range())` returns a `MastodonRequest<Pageable<ScheduledStatus>>`. Executing it sends a GET request to `api/v1/scheduled_statuses` and yields the caller's scheduled statuses. When a `Range` is given, its parameters are sent as query parameters (for example `limit=56` for `Range(limit = 56)`).
- `getScheduledStatus(withId: String)` returns a `MastodonRequest<ScheduledStatus>`. Executing it sends a GET request to `api/v1/scheduled_statuses/{id}` and yields that scheduled status.
- `updatePublishingDate(ofId: String, newPublishingDate: Instant)` returns a `MastodonRequest<ScheduledStatus>`. Executing it sends a PUT request to `api/v1/scheduled_statuses/{id}` that carries the new publishing time as the `scheduled_at` parameter, representing the same instant. Executing it yields the updated scheduled status.
- If `newPublishingDate` is not at least 5 minutes later than the current time, `updatePublishingDate` throws an `IllegalArgumentException` and no request is sent to the server.
- `cancelScheduledStatus(withId: String)` sends a DELETE request to `api/v1/scheduled_statuses/{id}`, returns nothing, and does not throw when the server responds successfully.

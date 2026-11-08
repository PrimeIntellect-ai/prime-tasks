Incomplete mastodon 3.0 support : use removed dissmiss notification endpoint
`POST /api/v1/notifications/dismiss?id=:id` is deprecated since 2.6 and removed since 3.0 (see https://github.com/tootsuite/mastodon/pull/11214)

I didn't make a PR because I don't know if you want your lib to be compatible with mastodon before 2.6.

### Additional contract requirements

Dismiss notifications with a POST to `/api/v1/notifications/{id}/dismiss`, using the notification's ID in the path rather than the removed legacy dismissal endpoint.

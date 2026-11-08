v0.28 RC: cannot access to `pagination` and `faceting` settings via the settings sub routes
Sorry if I missed something.
Version: v0.28.0rc0

When I get the settings using `GET /indexes/:uid/settings` I can see the `pagination` and `faceting` being present. I can even update them using `GET /indexes/:uid/settings`.

However I cannot get/update/reset them using the following endpoints
- `/indexes/:uid/settings/pagination`
- `/indexes/:uid/settings/faceting`

I get a `404`, these endpoints seem not to exist.

"is_admin_site" has the opposite meaning
`AxesHandler.is_admin_site()` actually checks if a `request.path` is *NOT* located under the `reverse("admin:index")`.

https://github.com/jazzband/django-axes/blob/ea4d3c477dd1fda2045ed8c927b6d0bb87200d27/axes/handlers/base.py#L136-L147

### Additional contract requirements

When `AXES_ONLY_ADMIN_SITE` is enabled, requests beneath the URL resolved by `reverse("admin:index")` must be subject to the normal access checks; requests outside that URL must bypass those checks. The admin-path classification must not depend on the setting being enabled.

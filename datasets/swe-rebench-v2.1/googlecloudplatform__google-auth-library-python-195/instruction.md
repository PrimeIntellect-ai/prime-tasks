GCE Credentials should not derive from Scoped
Because `with_scopes` raises `NotImplementedError`, the class cannot be used polymorphically where instances of `Scoped` are expected (see https://github.com/GoogleCloudPlatform/google-cloud-python/issues/3933).  For instance, in C++,`google.auth.compute_engine.credentials.Credentials` wouldn't even be instantiable, because `with_scopes` is a pure virtual method cognate.

If there is a need for *part* of the interface to be expressed (e.g., the `scopes`, `requires_scopes`, and `has_scopes` methods), that should be factored into another class (maybed `ReadonlyScoped`?), with the current `Scoped` class extending it.

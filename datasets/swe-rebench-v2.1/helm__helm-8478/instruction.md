Dependencies: Resolve version when only URL is known
Currently, when is resolving dependencies and a dependency is specified as a URL but it has not been added to Helm via `helm repo add` the dependency is locked to the exact value specified for the requested dependency. If the specified value is a range (e.g., `^1.2.3) the range is the version it is locked to.

The current situation creates a situation where locking isn't really locked to a version.

With more distributed repos that cross link each other this problem has the potential to get worse.

Instead of locking to the range, Helm should work out the version and lock to the version.

I would suggest the steps:

1. If not cached locally via `helm repo add`, create an automated and not-visible to the user cache.
2. Resolve the version from this invisible cache
3. Lock to the version
4. Clean up any invisible caches (periodically?)

### Additional contract requirements

- For a dependency whose repository is a URL that has not been added with `helm repo add`, obtain the repository information automatically without adding that repository to the user's repository configuration.
- When the requested version is a range, lock the concrete resolved chart version that satisfies the range, not the range itself.

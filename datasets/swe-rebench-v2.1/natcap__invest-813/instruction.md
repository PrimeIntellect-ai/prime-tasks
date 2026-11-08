Shapely 1.8 deprecation warnings
It looks like shapely `1.8.0` is out and it's a transitional release in prep for `2.0`.
https://shapely.readthedocs.io/en/stable/migration.html#migrating-to-shapely-1-8-2-0

There are some new deprecation warnings we can deal with while we're on `1.8.0`. And we should probably restrict our requirements to `<2.0`. I'm not sure exactly when 2.0 will drop.

I observed some warnings when running the CV sample data.

### Additional contract requirements

- When Coastal Vulnerability model operations run on sample data, they must not emit Shapely deprecation warnings introduced in Shapely 1.8. The deprecation warning for the `type` attribute is out of scope.
- Restricting Shapely requirements to versions below 2.0 is not required.

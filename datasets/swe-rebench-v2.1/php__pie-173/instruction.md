Cleanup on aisle `vendor`
After discussing with @derickr a bit, everything in the PIE working directory `vendor` except `vendor/composer/installed.json` is mostly just taking up space. It isn't used as a cache for subsequent (re)installs, so it is just taking up space.

Apparently Datadog ext is very large, so this could become problematic if we don't clean up. I imagine some kind of post install cleanup step can run that removes `vendor/*` (except `vendor/composer`), could work, although I need to investigate viability and impact.

### Additional contract requirements

After a successful PIE install, clean unused contents from the vendor directory in PIE's working directory to reduce wasted space. This cleanup must preserve `vendor/composer/installed.json`.

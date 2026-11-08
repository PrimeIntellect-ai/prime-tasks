[robots.txt parser] Deduplicate sitemap links
Deduplicate sitemap links contained in a robots.txt, see [NUTCH-2730](https://issues.apache.org/jira/browse/NUTCH-2730). Ideally, the collection should be still ordered with duplicates (optionally) removed.

### Additional contract requirements

- The sitemap links returned by `BaseRobotRules.getSitemaps()` must preserve the robots.txt input order of each unique link’s first occurrence.

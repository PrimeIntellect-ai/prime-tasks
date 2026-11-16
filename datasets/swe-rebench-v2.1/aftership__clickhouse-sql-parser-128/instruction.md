cannot parse `SELECT` as argument to a function
It's possible to use SELECT as argument to function:

```
select 1, (select 70) as `power`, number
from numbers(plus(ifNull(
        (SELECT 1 AS bin_count), 1), 1))
```

Here's a query I've tried to parse to test the parser:
https://github.com/PostHog/posthog/blob/40f632057891ffc614489e3a7942445e14db6a85/posthog/api/test/__snapshots__/test_insight_funnels.ambr

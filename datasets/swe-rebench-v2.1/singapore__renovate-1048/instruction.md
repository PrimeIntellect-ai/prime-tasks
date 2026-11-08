Renovate not checking day of month in schedule
:wave: maybe I'm not understanding how it should work but renovate has opened multiple PRs this month like this: https://github.com/Siilwyn/css-declaration-sorter-atom/pull/58

In the PR it states the schedule is: "before 3am on the first day of the month", doesn't seem to follow this though.

Config:
```json
{
  "extends": ["config:semverAllMonthly"]
}
```

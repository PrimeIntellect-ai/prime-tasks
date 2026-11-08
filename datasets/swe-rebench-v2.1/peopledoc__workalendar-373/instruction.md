Turkey calendar
As a follow up to @tayyipgoren's work and information. We need to:

- [x] Implement the ability to add a delta to islamic days, depending on the country context, or even the year (since the beginning of the Ramadan is subject to arbitrary decisions for example). By default, no delta is added.
- [x] Turkey's calendar is subject to substract one day to each Islamic holidays.
- [x] Rebase @tayyipgoren branch to align with the latest master, squash extra commits etc,
- [x] Add tests for the shifting New Year's Day if it happens on Sunday.
- [ ] Question for @tayyipgoren : could you please confirm that the "WEEKEND_DAYS" are Saturday and Sunday?

### Additional contract requirements

Expose the Turkey holiday calendar as `Turkey` in `workalendar.europe.turkey`. Calendars that compute Islamic holidays must allow a calendar-specific adjustment to be selected for each Gregorian year through `get_delta_islamic_holidays(year)`. A returned `datetime.timedelta` adjusts the Islamic-holiday dates for that year; returning `None`, including the default when no adjustment is configured, leaves them unchanged. Turkey applies an adjustment of one day earlier in every year.

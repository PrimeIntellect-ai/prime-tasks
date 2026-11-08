HK has not yet implemented Sat shift
        # Boxing day & XMas shift
[HIDDEN]
        days.extend(shifts)

so for 2020, Dec 28 (Mon) is not a holiday, please fix

### Additional contract requirements

- In the `HongKong` calendar, Saturdays are working days. A public holiday that
  falls on a Saturday is **not** shifted to the following Monday. In particular,
  Boxing Day 2020 falls on a Saturday, so 28 December 2020 must **not** be a
  holiday.
- `HongKongBank.holidays_set(year)` returns the same set of holidays as
  `HongKong.holidays_set(year)`.

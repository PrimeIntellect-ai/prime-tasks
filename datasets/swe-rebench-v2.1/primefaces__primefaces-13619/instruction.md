DatePicker: firstDayWeekOffset not calculated / IndexOfOutBound while submitting
It was introduced here: #5713


i have the problem when i enable week selection (like in the showcase) and set firstDayOfWeek=2, that firstDayWeekOffset is not caulcated. SundayIndex will become 5:

```
            var sundayIndex = this.getSundayIndex();
            if (this.options.locale.firstDayWeekOffset === undefined) {
                if (sundayIndex == 0) {
                    this.options.locale.firstDayWeekOffset = 6;
                }
                else if (sundayIndex == 1) {
                    this.options.locale.firstDayWeekOffset = 12;
                }
                else if (sundayIndex == 6) {
                    this.options.locale.firstDayWeekOffset = 4;
                }
                else {
                    this.options.showWeek = false;
                }
            }
```

@fanste i dont understand everything at all. Do you have a idea?

### Additional contract requirements

When week selection is enabled and the configured first day of week is such that the week offset cannot be computed (for example `firstDayOfWeek=2`, where `SundayIndex` becomes 5), the submitted range value can arrive without a week suffix. Parsing such a submitted value must not fail with an index-out-of-bounds error: `CalendarUtils.splitRange(input, datePattern, rangeSeparator, true)` must return the two range endpoints when `input` contains the range separator, regardless of whether `input` carries a trailing week suffix such as ` (Wk 21)`.

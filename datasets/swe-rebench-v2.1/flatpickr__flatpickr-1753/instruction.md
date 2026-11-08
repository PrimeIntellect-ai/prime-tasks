jumpToDate() does not trigger any events
jumpToDate() does not trigger events like onMonthChange, onYearChange, or onChange. Not sure if it's intended to, but it's odd. 🤷‍♂️

https://codepen.io/tako1337/pen/VNzOrB

## Your Environment
flatpickr version used: 4.5.7
Browser name and version: Chrome 73
OS and version: Windows 10

### Additional contract requirements

- `jumpToDate` is a public method on a flatpickr instance with the signature `jumpToDate(date?: DateOption, triggerChange?: boolean): void`.
- When `triggerChange` is `true` and the jump changes the displayed month, the `onMonthChange` callback is invoked.
- When `triggerChange` is `true` and the jump changes the displayed year, the `onYearChange` callback is invoked.
- When `triggerChange` is omitted or `false`, the jump does not invoke `onMonthChange` or `onYearChange`.

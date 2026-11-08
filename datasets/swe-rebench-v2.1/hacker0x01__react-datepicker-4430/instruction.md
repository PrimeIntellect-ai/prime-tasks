Keyboard accessibility not aligned with ARIA authoring practices guide
**Describe the bug**
Some of the keyboard shortcuts are not aligned to what the W3C WAI-ARIA.
[Date Picker Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/examples/datepicker-dialog/)
Like the Home and End button should go to the first and last day of the week.

**To Reproduce**
Steps to reproduce the behavior:

1. Open the calendar
2. Press Home on keyboard
3. Previous year is selected

**Expected behavior**
Should move the selected day to the first day of the week.

### Additional contract requirements

Pressing End while navigating the calendar moves the selected day to the last day of its week.

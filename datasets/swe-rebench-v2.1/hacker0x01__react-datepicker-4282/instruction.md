Changing time is resetting date to current date
**Describe the bug**
When we manually change the time value, the date value is reset to the current date.

**To Reproduce**
1. Considering current date is `sept 20th`
2. Pick `sept 21th` in the calendar picker
3. Modify the time in the time picker
4. The date is reset to `sept 20th`

**Expected behavior**
Changing the time in the time picker should not alter the selected date

**Additional context**
Bug seems to have appeared with the release of version 4.18.0.
Had to lock the version to 4.17.0 to fix the problem.

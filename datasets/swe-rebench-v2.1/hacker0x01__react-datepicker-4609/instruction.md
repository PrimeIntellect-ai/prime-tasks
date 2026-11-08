calendarStartDay and showWeekPicker, selected week is not active
**Describe the bug**
A clear and concise description of what the bug is.
When showWeekPicker is set true and calendarStartDay is set to 1, then only the first day of the week gets active state.
If calendarStartDay prop is removed it works as intended.

**To Reproduce**
Steps to reproduce the behavior:
1. Create datepicker as following:
2.  `<DatePicker selected={date} startDate={x} onChange={setDate} showWeekPicker={true} />`
3.  Check that after selecing week and reopening calendar it is in selected state
4. add calendarStartDay prop:  `<DatePicker calendarStartDay={1} selected={x} startDate={x} onChange={setX} showWeekPicker={true} />`
5. select week
6. selected week is not in active state

**Expected behavior**
A clear and concise description of what you expected to happen.
selected week should be in active state

**Screenshots**
If applicable, add screenshots to help explain your problem.
<img width="232" alt="Screenshot 2024-01-14 at 23 53 56" src="https://github.com/Hacker0x01/react-datepicker/assets/5435960/40cbe8f7-a30a-4b74-8c69-32506bc20480">
<img width="232" alt="Screenshot 2024-01-14 at 23 54 21" src="https://github.com/Hacker0x01/react-datepicker/assets/5435960/eaa784b5-a78d-4551-a0f9-bbb1a79ef13b">


**Desktop (please complete the following information):**

- OS: [e.g. iOS]
- Browser [e.g. chrome, safari]
- Version [e.g. 22]

**Smartphone (please complete the following information):**

- Device: [e.g. iPhone6]
- OS: [e.g. iOS8.1]
- Browser [e.g. stock browser, safari]
- Version [e.g. 22]

**Additional context**
Add any other context about the problem here.

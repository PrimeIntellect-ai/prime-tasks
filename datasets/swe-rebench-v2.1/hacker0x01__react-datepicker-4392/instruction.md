Clear button is active when input has a date inside and it is disabled
**Describe the bug**
While having a selected date with isClearable and disabled, the clear button is active and if clicked removes the date.

**To Reproduce**
Steps to reproduce the behavior:

```
const [startDate, setStartDate] = useState(new Date());

<DatePicker
  selected={startDate}
  onChange={(date) => setStartDate(date)}
  isClearable={true}
  disabled
/>
```

**Expected behaviour**
The clear button should be not active.

**Screenshots**
![image](https://user-images.githubusercontent.com/7200930/105151184-53e33100-5b0e-11eb-9c3c-78ec4f27d753.png)


**Desktop (please complete the following information):**

- OS: Windows (latest)
- Browser Chome (latest)
- Version 3.4.1

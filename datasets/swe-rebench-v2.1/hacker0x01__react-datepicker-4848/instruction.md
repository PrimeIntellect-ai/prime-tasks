Keyboard navigation is disabled if minDate or maxDate are `null`
**Describe the bug**
If minDate or maxDate have a value of `null` keyboard navigation thought days is disabled.

**To Reproduce**
Steps to reproduce the behavior:

render:
```jsx
<ReactDatePicker
   minDate={null}
   maxDate={null}
/>
```

**Expected behavior**
Keyboard navigation should be enabled.

**Desktop**

 Any OS or browser

**Additional context**
I ran into this issue because @types/react-datepicker defined type for `minDate` and `maxDate` as `Date | null | undefined`.
type for `minTime` and `maxTime` is `Date | undefined`.

I can make the edit on @types/react-datepicker, could you please confirm that the types for `minDate` and `maxDate` should be `Date | undefined` ?

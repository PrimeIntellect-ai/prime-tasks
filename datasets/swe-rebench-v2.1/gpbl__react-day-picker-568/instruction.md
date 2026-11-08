Move input related props to `inputProps`
In DayPickerInput, we are spreading input props from the component, e.g.:

```jsx
// Will render
// <input name="birthday" autocomplete={false} placeholder="Enter a date" />
<DayPickerInput
    name="birthday"
    autocomplete={false}
    placeholder="Enter a date"
/>
```

We are also using props that are not compatible with `input`, or that may override `input` props:

```jsx
<DayPickerInput
    format="LL" /* format will not be passed down to <input> */
    name="birthday"
    autocomplete={false}
    placeholder="Enter a date"
/>
```

This may create issues as React 16 now supports custom dom attributes should pass https://reactjs.org/blog/2017/09/26/react-v16.0.html#support-for-custom-dom-attributes

So to fix it, we should add a `inputProps` prop similar to what `dayPickerProps` does:

**Before**

```jsx
<DayPickerInput
    name="birthday"
    autocomplete={false}
    placeholder="Enter a date"
/>
```

**After**

```jsx
<DayPickerInput
    inputProps={{
        name: 'birthday',
        autocomplete: false,
        placeholder: 'Enter a date'
    }}
/>
```

Strange output for toString method while using preact-i18n
Hello! I was trying the latest rc.7 to port my snapshot tests from manually use `preact-render-to-string` to this library built-in solution.

One glitch I found is when I try to snapsnot an element which uses [preact-i18n](https://github.com/synacor/preact-i18n).

This is my component method:

```jsx
export const Select = ({ name, value, options, htmlFor, onBlur, onChange }) => {
    return (
        <select
            name={name}
            value={value}
            onChange={onChange}
            onBlur={onBlur}
            id={htmlFor}
        >
            <option value=""><Text id="select">Select</Text></option>
            {options.map(({ value, label }, i) => <option key={i} value={value}>{label}</option>)}
        </select>
    );
}
```

This is the output of `preact-render-to-string/jsx`:
```jsx
<select
    name="foo"
    id="foo"
>
    <option value="">Select</option>
    <option value={1}>bar</option>
    <option value={2}>baz</option>
</select>
```

While this is the output of `preact-render-spy` snapshot:
```jsx
preact-render-spy (1 nodes)
    -------
    <select
      name="foo"
      id="foo"
    >
      <option value="">[object Object]</option>
      <option value={1}>bar</option>
      <option value={2}>baz</option>
    </select>
```

Notice how the `<Text id="select">Select</Text>` is render as `[object Object]` in the snapshot.

Not sure if that's a problem only of `preact-i18n` though.

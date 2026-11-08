Add support for custom widget components
```js
function MyCustomWidget(props) {
  const {placeholder, value, defaultValue, required, onChange} = props;
  return (
    <div className="my-custom-widget">
      <em>I am a custom widget with value {value}.</em>
      <input type="text"
        value={value}
        defaultValue={defaultValue}
        placeholder={placeholder}
        required={required}
        onChange={(event) => onChange(event.target.value)} />
    </div>
  );
}

const uiSchema = {
  foo: {widget: MyCustomWidget}
}
```

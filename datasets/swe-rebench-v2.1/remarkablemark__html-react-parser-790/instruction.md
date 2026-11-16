`value=` shouldn't be converted to `defaultValue=` for `<option>`
The value of `<option>` tags of `<select>` are fixed. Converting their `value=` to `defaultValue=` results bug if the option label is different from the value. For example:

```html
<select name="range" value="gte-2">
  <option value="lt-1">Less than 1</option>
  <option value="gte-2">≥2<option>
</select>
```

The value of `<select>`'s "gte-2" won't get a match and it will fallback to "Less than 1".

https://github.com/remarkablemark/html-react-parser/blob/cffffc71fe8e72e6a662de50c0b00a3d77c60cc6/lib/attributes-to-props.js#L42-L49

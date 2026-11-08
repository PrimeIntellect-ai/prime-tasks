Cannot enter decimal value for number type
__Steps to reproduce:__

1. Navigate to "Numbers" tab in [live demo](http://mozilla-services.github.io/react-jsonschema-form/)
2. Select and backspace Number field to clear it
3. Once reset to 0, attempt to enter "3.14"
4. Note that it is not possible

__Expected cause:__

When [change event occurs](https://github.com/mozilla-services/react-jsonschema-form/blob/daca36b57c8ceea1cb932b062847372b1848850d/src/components/fields/NumberField.js#L9) upon entering the decimal value, the value "3." will cast to integer value `3`, thus removing the decimal and preventing the user from entering their desired value.

In other words:

```js
console.log( Number( '3.' ) );
// => 3
```

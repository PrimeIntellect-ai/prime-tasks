Improve translation component
Now if translation is passed a null or undefined value in passThrough prop, it will display the string null or the string undefined. It should rather return null than the string null.

### Additional contract requirements

- If `passThrough` is `null`, the translation component returns `null` rather than rendering the text `null`.
- If `passThrough` is `undefined`, the translation component returns `null` rather than rendering the text `undefined`.

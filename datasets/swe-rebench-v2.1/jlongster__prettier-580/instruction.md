Unnecessary parentheses in jsx
Input:
```js
const tabs = [
    {
        title: 'General Info',
        content: (
            <GeneralForm
                long-attribute="i-need-long-value-here"
                onSave={ onSave }
                onCancel={ onCancel }
                countries={ countries }
            />),
    },
];
```

Output:
```js
const tabs = [
    {
        title: "General Info",
        content: (
            (
                <GeneralForm
                    long-attribute="i-need-long-value-here"
                    onSave={onSave}
                    onCancel={onCancel}
                    countries={countries}
                />
            )
        )
    }
];
```

https://jlongster.github.io/prettier/#%7B%22content%22%3A%22const%20tabs%20%3D%20%5B%5Cn%20%20%20%20%7B%5Cn%20%20%20%20%20%20%20%20title%3A%20'General%20Info'%2C%5Cn%20%20%20%20%20%20%20%20content%3A%20(%5Cn%20%20%20%20%20%20%20%20%20%20%20%20%3CGeneralForm%5Cn%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20long-attribute%3D%5C%22i-need-long-value-here%5C%22%5Cn%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20onSave%3D%7B%20onSave%20%7D%5Cn%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20onCancel%3D%7B%20onCancel%20%7D%5Cn%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20countries%3D%7B%20countries%20%7D%5Cn%20%20%20%20%20%20%20%20%20%20%20%20%2F%3E)%2C%5Cn%20%20%20%20%7D%2C%5Cn%5D%3B%22%2C%22options%22%3A%7B%22printWidth%22%3A120%2C%22tabWidth%22%3A4%2C%22singleQuote%22%3Afalse%2C%22trailingComma%22%3Afalse%2C%22bracketSpacing%22%3Atrue%2C%22doc%22%3Afalse%7D%7D

### Additional contract requirements

The "Output" block above is the current, buggy rendering reported by the issue: the JSX element used as an object property value is wrapped in a redundant extra pair of parentheses. The requested fix removes that redundant inner pair. For the supplied input, the expected output is:

```js
const tabs = [
    {
        title: "General Info",
        content: (
            <GeneralForm
                long-attribute="i-need-long-value-here"
                onSave={onSave}
                onCancel={onCancel}
                countries={countries}
            />
        )
    }
];
```

That is, a JSX element used as an object property value must not gain an extra wrapping pair of parentheses beyond the single pair already required around the JSX element.

How can I pass a default value for the case of a non-existent or empty-string translation?
### Example

In every non-English language, I have a translation for the `warningMessage` variable. In the example, I copied the German file. The text in English is: _Attention! The original language of the page is English. You are currently browsing a page translated into German by the community. If you encounter any errors, please let us know!_

Naturally, I don't want to display it in English, so in the English file, I declare an empty string (to avoid discrepancies between the two files).

**de.json**
```json
{
  "warningMessage": "Achtung! Die Originalsprache der Seite ist Englisch. Sie durchsuchen gerade eine von der Gemeinschaft ins Deutsche übersetzte Seite. Wenn Sie Fehler bemerken, lassen Sie es uns bitte wissen!",
}
```

**en.json**
```json
{
  "warningMessage": "",
}
```

### Problem

However, **when I invoke the `trans('warningMessage')` function in English, it returns `warningMessage` instead of an empty string**. How can I provide the function with a default value for the case of an empty string or undeclared variable?

### Solution?

I temporarily added a space to the text. However, in this case, the length of the text is not 0 but 1, which is illogical for an empty string. Is there another solution? I would like to instruct the `trans` function to output nothing in the case of a 0-length string value in this situation.

**en.json**
```json
{
  "warningMessage": " ", // space
}
```

### Request

I think it would be perfectly fine to leave the `trans` function as it is and create another function, perhaps named `nullableTrans` or any other name, whose purpose is to avoid outputting the key as a result when the key does not exist or its value is of zero length.

While displaying the key is very useful, there are a few cases across multiple projects where I want to avoid it without having to modify the `trans` function everywhere afterward.

**de.json**
```json
{
  "warningMessage": "Achtung! ...",
}
```

```js
trans("warningMessage") // result: "Achtung! ..."
nullableTrans("warningMessage") // result: "Achtung! ..."
```

**en.json**
```json
{
  "warningMessage": "",
}
```

```js
trans("warningMessage") // result: "warningMessage"
nullableTrans("warningMessage") // result: ""
```

**cz.json**
```json
{
  "anotherKey": "...",
  // warningMessage not declared
}
```

```js
trans("warningMessage") // result: "warningMessage"
nullableTrans("warningMessage") // result: ""
```

### Additional contract requirements

- The behavior is provided by the existing `trans` function: when the resolved translation value is an empty string (zero length), `trans` must return an empty string instead of the key.
- When the key is not present in the loaded language files, the existing behavior is preserved: `trans` returns the key.

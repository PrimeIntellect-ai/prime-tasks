throwOnInvalid does not throw for invalid year
**Describe the bug**
When setting `Settings.throwOnInvalid`, Luxon does not seem to throw an error if the year is too large (both positive or negative), even though `dateTime.isValid` will return `false`.

**To Reproduce**

```ts
luxon.Settings.throwOnInvalid = true;

const dateTime = luxon.DateTime.fromObject({ year: 1000000 });
console.log(dateTime.isValid, dateTime.invalidReason);
```

**Actual vs Expected behavior**

Expected: An error is thrown

Actual: `false invalid input` is logged to the console

**Desktop:**

- OS: macOS 13.4
- Browser: Chrome 114
- Luxon version: 3.3.0
- Your timezone: Europe/Berlin

Thanks for looking into it!

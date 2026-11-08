Timezone offsets are output with long decimals from floating point rounding errors in Firefox
This issue is present in Firefox 77. Timezone offsets, whether output by the format string token "ZZZ" or the toISO() method, have long floating point rounding errors in the minutes portion of the offset (i.e. `50.6000000000000002` rather than `50`)

Here are two examples:

```
> DateTime.fromJSDate(new Date(-62090696591000)).toFormat(`yyyy-MM-dd'T'HH:mm:ss.SSSZZ`)
 "0002-06-04T10:26:13.000-05:50.60000000000002"
```

```
> DateTime.fromJSDate(new Date(-62090696591000)).toISO()
"0002-06-04T10:26:13.000-05:50.60000000000002"
```

I believe that the root of the problem is that for this particular timestamp, Firefox returns 350.6 as the timezone offset:
```
> new Date(-62090696591000).getTimezoneOffset()
350.6
```

[HIDDEN]

### Additional contract requirements

- Timezone offsets produced by `toISO()` and `toFormat("ZZZ")` must represent the minutes component as an integer, without floating-point fractions.

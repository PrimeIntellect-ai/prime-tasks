Hex value exported into JSON, but JSON does not support hex literals
Taking:

```
> cat /tmp/i.csv
a,b
foo,0x123
```

I get:
```
> mlr --icsv --ojson cat /tmp/i.csv
[
{
  "a": "foo",
  "b": 0x123
}
]
```

But `0x123` is not a valid JSON value:
```
> mlr --icsv --ojson cat /tmp/i.csv | jq
jq: parse error: Invalid numeric literal at line 5, column 0
```

Tested with:
```
> mlr --version
mlr 6.13.0
```

---

One probably wants to either export it as base 10 number or as string:

```
[
{
  "a": "foo",
  "b": "0x123"
}
]
```
or:
```
[
{
  "a": "foo",
  "b": 291
}
]
```

### Additional contract requirements

- When an integer is formatted in hexadecimal, JSON output must encode its value as a base-10 number; for example, emit `12345` rather than `0x3039` or `"0x3039"`.

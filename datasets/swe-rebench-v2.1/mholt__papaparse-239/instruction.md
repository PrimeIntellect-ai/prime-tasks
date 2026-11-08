Incorrect result when last record ends with an empty quoted value
Consider this example:
```csv
a,1,""
b,2,""
c,3,""
```
Parsing this structure results in the following data:
```json
[
    [
        "a",
        "1",
        ""
    ],
    [
        "b",
        "2",
        ""
    ],
    [
        "c",
        "3",
        "\""
    ]
]
```
Notice that the last string value contains an extra double quote, which is incorrect IMHO. I'd at least expect every record to be treated equally.

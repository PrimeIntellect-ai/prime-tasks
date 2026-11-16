Nested Array/Dictionary/DictionaryArrays are not parsed with their proper nesting
Related to #48
See this example:
```
/OCProperties <<
    /D <<
        /AS [
            <<
                /Category [/Print]
                /Event/Print
                /OCGs [939 0 R 419 0 R]
            >>
            <<
                /Category [/View]
                /Event/View
                /OCGs[939 0 R 419 0 R]
            >>
        ]
        /BaseState/OFF
        /ON[419 0 R]
        /Order[]
        /RBGroups[]
    >>
    /OCGs[939 0 R 419 0 R]
>>
```

The 5th row already closes one level of nesting too early, as the closing square bracket for the [/Print] section also closes the /AS DictionaryArray

### Additional contract requirements

When parsing nested arrays and dictionaries, each closing bracket must close only its matching array. Parsing must then continue within the containing dictionary, so later values and entries remain associated with their proper enclosing dictionaries.

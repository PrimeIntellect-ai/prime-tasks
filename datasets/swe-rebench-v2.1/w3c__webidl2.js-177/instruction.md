Error parsing generic type with Promise<void>
Parsing https://github.com/w3c/web-platform-tests/blob/master/interfaces/BackgroundSync.idl is broken by https://github.com/w3c/webidl2.js/commit/621d0b6c17c6f34cf6b0b5c0976abb069703d4eb.

```
Got an error during or right after parsing `interface SyncManager`: Error parsing generic type Promise, line 11 (tokens: "void> register(DOMString")
[
    {
        "type": "void",
        "value": "void",
        "trivia": ""
    },
    {
        "type": "other",
        "value": ">",
        "trivia": ""
    },
    {
        "type": "identifier",
        "value": "register",
        "trivia": " "
    },
    {
        "type": "other",
        "value": "(",
        "trivia": ""
    },
    {
        "type": "identifier",
        "value": "DOMString",
        "trivia": ""
    }
]
```

It looks like the relevant IDL is:

```
[Exposed=(Window,Worker)]
interface SyncManager {
  Promise<void> register(DOMString tag);
  Promise<sequence<DOMString>> getTags();
};
```

### Additional contract requirements

- `ByteString`, `DOMString`, and `USVString` are recognized as string type keywords. As a result, a `const` declaration whose type is one of these string types (for example `const DOMString hello = "world";`) is rejected with the error message `No type for const`.

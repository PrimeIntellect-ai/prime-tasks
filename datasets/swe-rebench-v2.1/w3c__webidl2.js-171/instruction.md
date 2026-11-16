Trailing comma in arguments list with valid IDL
Parsing https://github.com/w3c/web-platform-tests/blob/master/interfaces/dom.idl is broken in the latest version, not sure when it broke.

```
Got an error during or right after parsing `interface EventTarget`: Trailing comma in arguments list, line 54 (tokens: "? callback, optional (")
[
    {
        "type": "other",
        "value": "?",
        "trivia": ""
    },
    {
        "type": "callback",
        "value": "callback",
        "trivia": " "
    },
    {
        "type": "other",
        "value": ",",
        "trivia": ""
    },
    {
        "type": "optional",
        "value": "optional",
        "trivia": " "
    },
    {
        "type": "other",
        "value": "(",
        "trivia": " "
    }
]
```

This is referencing parsing:

```
[Constructor,
 Exposed=(Window,Worker)]
interface EventTarget {
  void addEventListener(DOMString type, EventListener? callback, optional (EventListenerOptions or boolean) options);
  void removeEventListener(DOMString type, EventListener? callback, optional (EventListenerOptions or boolean) options);
  boolean dispatchEvent(Event event);
};
```

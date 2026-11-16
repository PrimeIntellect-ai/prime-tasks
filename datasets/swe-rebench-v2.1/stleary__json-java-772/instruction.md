Logic to exclude object keys that are themselves objects is imperfect
`JSONObject` contains [this logic](https://github.com/stleary/JSON-java/blob/01727fd0ed00c1f1f5582bdc97244356ac029f3b/src/main/java/org/json/JSONObject.java#L218-L222) to prevent a key in a JSON object from being another JSON object or an array:
```java
            case '{':
            case '[':
                if(prev=='{') {
                    throw x.syntaxError("A JSON Object can not directly nest another JSON Object or JSON Array.");
                }
```
However this doesn't cover all cases. For example, `JSONObject` currently accepts this string:
```
{"a":1, [{"b": 2}]: 3}
```
which it interprets as an object with two keys, one that is the string `a` and one that is the string `[{"b":2}]`.

Strict JSON, of course, only accepts string literals as keys in objects. JSON-java is more liberal, but it does balk at nested objects since the fix for #654. The example above suggests that that fix was incomplete. I think it would make sense to disallow nested objects or arrays as keys always. They're not valid JSON and it's unlikely that anyone is relying on them for legitimate purposes. Meanwhile they can straightforwardly be used for DoS attacks, similar to #654 and #758.

I have a proposed fix which I will send shortly.

### Additional contract requirements

- For the input `{{"foo": "bar"}: "baz"}`, the `JSONException` message must be exactly `Missing value at 1 [character 2 line 1]`. For `{"a": 1, [{"foo": "bar"}]: "baz"}`, it must be exactly `Missing value at 9 [character 10 line 1]`. For `{foo}: 2}` and `{foo]: 2}`, it must be exactly `Expected a ':' after a key at 5 [character 6 line 1]`.

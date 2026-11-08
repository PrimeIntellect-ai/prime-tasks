'NoneType' object has no attribute 'encode'
We have noticed failures with CustomScriptForLinux with the following error message.

```text
'NoneType' object has no attribute 'encode'
```

This may affect other extensions in this repo, but the only report we have is for CustomScript.

### Additional contract requirements

- Setting an extension handler's status must complete without raising when the status document it produces cannot be serialized into a payload (the serialized result is `None`). The call returns normally instead of surfacing the `'NoneType' object has no attribute 'encode'` error.

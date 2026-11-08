Failure to represent empty dictionary
I have nested an empty dictionary and YAMS fails to convert it to YAML:
```
failed: caught error: "Failed to represent {
    emptydict =     {
};
```

An empty dictionary should be represented as `{}`.

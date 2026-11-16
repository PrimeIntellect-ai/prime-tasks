rewrite screenshots blocks timestamp with creation time
+ Currently screenshot block `timestamp` is based on screenshot blob construction time instead of when the screenshot was taken. As a result, the screenshot timestamp would be greater than the journey/end timestamp which is not true.


### Wrong order
```
-- step/end timestamp
-- journey/end timestamp

--- screenshot/block timestamp
--- screenshot/block timestamp

-- end timestamp
```

#### Correct order
```
-- screenshot/block timestamp
-- screenshot/block timestamp

-- step/end timestamp
-- journey/end timestamp
-- end timestamp
```

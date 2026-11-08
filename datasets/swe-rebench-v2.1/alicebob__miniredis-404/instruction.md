BLMOVE to the same single-element list causes TTL to be lost
This sequence of Redis commands:

```
LPUSH test 1
EXPIRE test 1000
TTL test  # outputs TTL > 0
BLMOVE test test LEFT LEFT 1
TTL test  # should continue outputting TTL > 0
```

works with Redis, but not Miniredis: The final `TTL test` in Miniredis will return -1, since I think blmove's implementation in Miniredis will cause Miniredis to delete and recreate the `test` list, losing the TTL in the process.

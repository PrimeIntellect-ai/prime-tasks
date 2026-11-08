Iterator order inconsistency with jq
There's inconsistency with jq for the following case.
```sh
 % echo '{"x": ["a", "b"], "y": [{"a": 1, "b": 3}, {"a": 2, "b": 4}] }' | jq '.y[][.x[]]'
1
2
3
4
 % echo '{"x": ["a", "b"], "y": [{"a": 1, "b": 3}, {"a": 2, "b": 4}] }' | java -jar jackson-jq-cli-1.0.0-preview.20191208.jar '.y[][.x[]]'
1
3
2
4
```

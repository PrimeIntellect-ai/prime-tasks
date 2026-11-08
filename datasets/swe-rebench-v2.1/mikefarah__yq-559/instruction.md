JSON conversion (still) does not preserve object order
**Describe the bug**

It seems from #274 having been fixed that conversion to JSON should now be preserving object order, but that's not what I'm seeing.

**Input Yaml**
data1.yml:
```yaml
foo: a
bar: b
```

**Command**
```
yq r -jP data1.yaml
```

**Actual behavior**
```json
{
  "bar": "b",
  "foo": "a"
}
```

**Expected behavior**
```json
{
  "foo": "a",
  "bar": "b"
}
```

**Additional context**
yq version 3.3.0 on macOS 10.15.3

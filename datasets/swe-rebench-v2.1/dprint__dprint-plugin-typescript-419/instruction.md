useBraces=whenNotSingleLine adds braces when conditional spans multiple lines
**Describe the bug**

dprint-plugin-typescript version: 0.73.0

```
{
  "indentWidth": 4,
  "useBraces": "whenNotSingleLine",
  "singleBodyPosition": "maintain"
}
```

**Input Code**

```ts
if (someFunction({
    xyz: 1234
})) return;
```

**Expected Output**

```ts
if (
    someFunction({
        xyz: 1234,
    })
) return;
```

**Actual Output**

```ts
if (
    someFunction({
        xyz: 1234,
    })
) { return; }
```

Setting `"singleBodyPosition": "maintain"` fixes this. Probably similar in vein to #359.

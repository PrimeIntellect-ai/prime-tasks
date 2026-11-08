IndexOutOfRangeException when using IContextStore.Set
I get `IndexOutOfRangeException `while using `IContextStore.Set`. Looks like a bug in `TypedDictionary`

bacause:
`private static int typeIndex = -1;`

when we use `Add`:

```
public void Add<TKey>(TValue value)
    {
        lock (_lockObject)
        {
            var id = TypeKey<TKey>.Id;

            if (id >= _values.Length)
            {
                [HIDDEN]
            }

            _values[id] = value;
        }
    }
```

[HIDDEN]

### Additional contract requirements

- The first call to `IContextStore.Set` for a value must complete without throwing `IndexOutOfRangeException`, and the value must be retrievable.

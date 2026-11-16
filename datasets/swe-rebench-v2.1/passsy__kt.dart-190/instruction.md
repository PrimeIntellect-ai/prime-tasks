KMutableEntry.setValue doesn't change value in collection
`KMutableEntry.setValue` doesn't change the underlying collection. Here is a valid test which is currently failing

```dart
final pokemon = mutableMapOf({
  1: "Bulbasaur",
  2: "Ivysaur",
});

pokemon.entries.forEach((entry) {
  entry.setValue(entry.value.toUpperCase());
});

// throws because pokemon is unchanged
expect(
    pokemon,
    mapOf({
      1: "BULBASAUR",
      2: "IVYSAUR",
    }));
```

### Additional contract requirements

- `setValue` must return the entry's value before it is changed.

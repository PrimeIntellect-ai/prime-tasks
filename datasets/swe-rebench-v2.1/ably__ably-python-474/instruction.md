`RSN4b`: Error raised
Spec point `RSN4b`:

```
Calling release() with a channel name that does not correspond to an extant channel entity must return without error
```

At the moment, calling release on a non-existent channel results in an error being raised due to it not appearing in the channel map.

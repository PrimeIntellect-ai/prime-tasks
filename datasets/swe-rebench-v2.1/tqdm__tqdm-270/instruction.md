Support custom metrics in progress bar format
It'd be nice to update custom metrics on the progress bar status. This would make tqdm super helpful for something like machine learning training where you want to know how well your model is doing.

e,g. before:

```
0%|3                                             | 27/6000 [08:24<28:42:16, 17.30s/it]
```

after:

```
0%|3                                | 27/6000 [08:24<28:42:16, 17.30s/it, 0.1233 loss]
```

### Additional contract requirements

- Custom metrics can be shown on a bar in two ways: pass a `postfix` mapping of metric names to values when creating the bar, or call `set_postfix()` with keyword arguments (`name=value`) on the bar at any time.
- Custom metrics are shown in the progress status after the ordinary progress information (the counter, percentage, elapsed and remaining time).
- Calling `set_postfix()` again while the bar is running replaces the displayed metric values with the new ones from the next refresh onward.

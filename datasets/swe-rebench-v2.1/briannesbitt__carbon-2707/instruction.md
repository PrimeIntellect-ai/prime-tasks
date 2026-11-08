diffForHumans gives wrong amount of days
Hello,

I encountered an issue with the following code:
```php
$deletedDate = Carbon::now()->startOfDay()->addDays(31);

echo $deletedDate->diffForHumans(Carbon::now()->startOfDay(), [
    'syntax' => CarbonInterface::DIFF_ABSOLUTE,
    'skip' => ['m', 'w'],
    'minimumUnit' => 'd'
]);;
```

Carbon version: 2.61.0

PHP version: 8.1.8

I expected to get:

```
31 days
```

But I actually get:

```
28 days
```

Thanks!

### Additional contract requirements

- `CarbonInterval::instance(DateInterval $interval, array $skip = [])` in `Carbon\CarbonInterval` returns a `CarbonInterval` for the given interval. The optional `$skip` list names units (shortcut or full name) to omit from the result; the total duration of the interval is preserved.
- `CarbonInterval::getDateIntervalSpec(DateInterval $interval, bool $microseconds = false, array $skip = [])` in `Carbon\CarbonInterval` returns the ISO-8601 specification string for the interval. The optional `$skip` list names units to omit from the specification; the total duration of the interval is preserved.
- `diffAsCarbonInterval($date = null, $absolute = true, array $skip = [])` on `Carbon` and `CarbonImmutable` returns the difference as a `CarbonInterval`. The optional `$skip` list names units to omit from the result; the total duration of the interval is preserved.


- Also, when the current time is fixed at `2021-11-04 15:42`, `Carbon::parse('2022-05-25')->diffForHumans(['skip' => ['y', 'm']])` must return `28 weeks from now`, and with `['skip' => ['y', 'm', 'w']]` it must return `201 days from now`. `Carbon::parse('2020-05-25')->diffForHumans(['skip' => ['y', 'm', 'w']])` must return `528 days ago`.

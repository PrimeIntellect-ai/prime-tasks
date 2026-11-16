setDateTimeClass is missing on OpeningHours::class
When creating the OpeningHours class using the static method createAndMergeOverlappingRanges, you are unable to set the DateTimeClass for that instance. You should be able to pass it via createAndMergeOverlappingRanges method, or a setDateTimeClass method must be available like in version 2.41.0.

### Additional contract requirements

- The DateTime class must be configurable by passing a `dateTimeClass` key in the array given to `createAndMergeOverlappingRanges`.
- The `dateTimeClass` key must be excluded from schedule parsing: it is neither a day name nor a time range, so it must not be interpreted as opening hours.
- When `dateTimeClass` is `DateTimeImmutable::class`, `nextOpen` must return a `DateTimeImmutable` instance.

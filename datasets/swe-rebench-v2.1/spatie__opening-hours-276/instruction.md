No close date/time found in the previous 8 days, use $openingHours->setDayLimit() to increase the limit.
It returns the error:
No close date/time found in the previous 8 days, use $openingHours->setDayLimit() to increase the limit.

Meanwhile, the schedule or data seems to be valid.

Schedule Data:
```php
$schedule = [
     "monday" => ["10:00-23:59"],
     "tuesday" => ["10:00-23:59"],
     "wednesday" => ["10:00-23:59"]
     "thursday" => ["10:00-23:59"]
     "friday" => ["10:00-23:59"]
     "saturday" => ["10:00-23:59"]
     "sunday" => ["10:00-23:59"]
];
```

We're using:
```php
$openingHours = OpeningHours::createAndMergeOverlappingRanges(
      data: $schedule,
      timezone: config('openinghours.timezone'), // Australia/Brisbane
)
```

```php
$now = new DateTime('2025-05-23 09:00:00', new DateTimeZone('Australia/Brisbane')); // Friday
$openingHours->previousClose($now);
```

Expected:
```php
Thu 23:59
```

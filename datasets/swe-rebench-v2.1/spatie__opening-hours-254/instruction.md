Unable to createFromStructureData after using `asStructuredData` on OpeningHours model
I'm trying to store `OpeningHours` in database as array and trying to do it like that:

```php
    $timetable = OpeningHours::create([
        'monday'     => ['09:00-12:00', '13:00-18:00'],
        'tuesday'    => ['09:00-12:00', '13:00-18:00'],
        'wednesday'  => ['09:00-12:00'],
        'thursday'   => ['09:00-12:00', '13:00-18:00'],
        'friday'     => ['09:00-12:00', '13:00-20:00'],
        'saturday'   => ['09:00-12:00', '13:00-16:00'],
        'sunday'     => [],
        'exceptions' => [
            '2016-11-11' => ['09:00-12:00'],
            '2016-12-25' => [],
            '01-01'      => [],                // Recurring on each 1st of January
            '12-25'      => ['09:00-12:00'],   // Recurring on each 25th of December
        ],
    ]);

    $array = $timetable->asStructuredData();
    $newOpeningHours = OpeningHours::createFromStructuredData($array);
```

But i'm getting an error: `Invalid openingHoursSpecification item at index 13: Invalid validFrom date`

How can I make it working?

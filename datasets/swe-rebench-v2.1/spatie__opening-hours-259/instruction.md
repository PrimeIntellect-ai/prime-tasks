nextClose Method Returns Incorrect Time when Overflow Enabled
Version: 4.0

The nextClose method does not return the expected result when using overflow and dealing with overnight hours. Below are some examples demonstrating the issue.

**Example 1: Working as Expected**
``` php
$openingHours = OpeningHours::create([
   'overflow' => true,
   'monday' => ['18:00-05:00'], // 2024-11-11
   'tuesday' => ['17:00-06:00'], // 2024-11-12
]);

$tuesday = new DateTime('2024-11-12 04:00:00');
echo 'Today      : ' . $tuesday->format('Y-m-d H:i') . "\n";
echo 'Next close : ' . $openingHours->nextClose($tuesday)->format('Y-m-d H:i') . "\n";
```

Output:
```
Today : 2024-11-12 04:00
Next close : 2024-11-12 05:00
```
This works as expected.

**Example 2: Issue with Overnight Hours**
When the time is set to "2024-11-12 05:30:00" (Which is currently closed)

``` php
$openingHours = OpeningHours::create([
   'overflow' => true,
   'monday' => ['18:00-05:00'], // 2024-11-11
   'tuesday' => ['17:00-06:00'], // 2024-11-12
]);

$tuesday = new DateTime('2024-11-12 05:30:00');
echo 'Today      : ' . $tuesday->format('Y-m-d H:i') . "\n";
echo 'Next close : ' . $openingHours->nextClose($tuesday)->format('Y-m-d H:i') . "\n";
```
Output:
```
Today : 2024-11-12 04:00
Next close : 2024-11-12 06:00
```
Expected Output:
```
Today : 2024-11-12 04:00
Next close : 2024-11-13 06:00
```
It incorrectly calculates the next closing time as the current day's 6:00 AM instead of the following day's.

**Example 3: Issue with Multiple Ranges and Overflow**

``` php
$openingHours = OpeningHours::create([
   'overflow' => true,
   'monday' => ['18:00-22:00', '23:00-05:00''], // 2024-11-11
   'tuesday' => ['17:00-06:00'], // 2024-11-12
]);

$tuesday = new DateTime('2024-11-12 04:00:00');
echo 'Today      : ' . $tuesday->format('Y-m-d H:i') . "\n";
echo 'Next close : ' . $openingHours->nextClose($tuesday)->format('Y-m-d H:i') . "\n";
```
Output:
```
Today : 2024-11-12 04:00
Next close : 2024-11-12 22:00
```
Expected Output:
```
Today : 2024-11-12 04:00
Next close : 2024-11-12 05:00
```

The next closing time should be 2024-11-12 05:00 but instead incorrectly jumps to the evening time range.

The nextClose method sometimes does not handle overnight hours correctly when overflow is enabled, particularly when the time is outside of any active range. It either skips to the wrong range or calculates the closing time incorrectly.

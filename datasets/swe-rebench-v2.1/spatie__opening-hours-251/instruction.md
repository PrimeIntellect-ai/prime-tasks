previousOpen returns next open date
Hi! We are using your library (2.41.0) and looking for a way to find last opening time. As I understand `previousOpen` should do this, but seems that response is not correct. I tried to setup next opening hours:
* Monday: 18:00 - 05:00
* Tuesday: 18:00 - 05:00
And `previousOpen` with (Tuesday 06:00) returns (Tuesday 18:00), but I expect (Monday 18:00). So it returns `nextOpen`.

Created a test file such as:
```php
$openingHours = OpeningHours::create([
    'overflow' => true,
    'monday' => ['18:00-05:00'],
    'tuesday' => ['18:00-05:00'],
]);
$tuesday = new DateTime('2024-06-11 06:00:00');
echo 'Today          : ' . $tuesday->format('Y-m-d H:i') . "\n";
echo 'Previous open  : ' . $openingHours->previousOpen($tuesday)->format('Y-m-d H:i') . "\n";
echo 'Previous close : ' . $openingHours->previousClose($tuesday)->format('Y-m-d H:i') . "\n";
```
Response
``` cmd
Today          : 2024-06-11 06:00
Previous open  : 2024-06-11 18:00
Previous close : 2024-06-11 05:00
```
Could you please say if there's a problem with configuration or there any solution to solve this issue?

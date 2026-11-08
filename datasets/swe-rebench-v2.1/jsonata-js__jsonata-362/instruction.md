Need a good way to locate elements in an array, or at least that element's index
I'm trying to do something that I thought would be easy, but running into some roadblocks...

As an example, let's try to convert an input Month abbreviation into the Date month number (0-based). It's easy to find out if the incoming string is in the array of months, using `payload in $months`, but finding out what position it occupies in the array is not so easy:
```
(
    $months := [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    $months~>$map(function($val, $idx) {
        $val = payload ? $idx : undefined
    })
)
```
A bit clunky, perhaps, but it returns the index number for every array element that is equal to the incoming string. I tried using the `$reduce($array, function($total, $value))` -- but unlike the Javascript function of the same name, there is no index value passed as the 3rd argument. **At a minimum, I think the `$reduce()` function should be extended to also pass $index as an optional argument**.

But perhaps a pair of new functions would be more intuitive and simpler to use, such as:
* `$find(array, input)` and the overloaded `$find(array, function($value))`
* `$indexOf(array, input)` and the overloaded `$indexOf(array, function($value))`

Both functions take an array of "things", and either a similar "thing" to find, or a function that determines which element is a match (returns true or false).

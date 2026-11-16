Reformation Day is now in more states (Germany)
https://www.timeanddate.com/holidays/germany/reformation-day

Currently there are 9 states that celebrate it, versus the 5 or so of previous years.

### Additional contract requirements

- German state calendars expose a public method `include_reformation_day(self, year)` that returns a boolean: `True` when Reformation Day (31 October) is a holiday for the given year, and `False` otherwise.
- The method returns `True` for every German state in 2017.
- A state that has always included Reformation Day returns `True` for every year.
- A state whose public `include_reformation_day_2018` attribute is true returns `True` for 2018 and every later year.
- Otherwise the method returns `False`.
- Bremen, Hamburg, Lower Saxony, and Schleswig-Holstein joined the annual observance in 2018. Their public `include_reformation_day_2018` attribute is true, so October 31 is included in each calendar from 2018 onward.

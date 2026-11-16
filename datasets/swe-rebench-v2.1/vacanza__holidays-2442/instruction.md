Add French Southern Territories holidays
URLs:
 - https://holidayapi.com/countries/tf/2022

### Additional contract requirements

- Add a public class `HolidaysTF` in the module `holidays.countries.french_southern_territories`.
- Add public classes `FrenchSouthernTerritories`, `TF`, and `ATF` in the same module; each is a
  subclass of `HolidaysTF` and behaves identically to it.
- A `HolidaysTF` instance exposes a public `subdiv` attribute whose value is `"TF"`.
- Holidays are supported from 1956 onward; years before 1956 have no holidays.

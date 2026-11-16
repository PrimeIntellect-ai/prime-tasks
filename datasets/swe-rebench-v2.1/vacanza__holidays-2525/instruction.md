Add Togo holidays
Links:
  - https://en.wikipedia.org/wiki/Public_holidays_in_Togo
  - https://www.timeanddate.com/holidays/togo/

### Additional contract requirements

- Add a public `Togo` holiday calendar class in module `holidays.countries.togo`, together with alias classes `TG` (ISO 3166-1 alpha-2 code) and `TGO` (ISO 3166-1 alpha-3 code) that behave identically to `Togo`.
- `Togo.__init__` accepts an optional `islamic_show_estimated: bool = True` argument that controls whether Islamic holidays whose dates are estimated receive the "(estimated)" label, and forwards all remaining arguments to the standard holiday calendar base class.
- The default language is French (`fr`); use these French holiday names: `Jour de l'an`, `Fête de la libération nationale`, `Lundi de Pâques`, `Fête de l'indépendance`, `Fête du travail`, `Fête de l'Ascension`, `Lundi de Pentecôte`, `Fête des Martyrs`, `Assomption`, `Toussaint`, `Noël`, `Ramadan`, `l'Aïd El-Fitr`, `Tabaski`, and `Anniversaire de l'attentat manqué contre Lomé`.
- Togo holidays are observed from 1961 onwards.
- `Anniversaire de l'attentat manqué contre Lomé` is a `WORKDAY`-category holiday observed from 1987 onwards; it is not part of the default public holidays.
- For `en_US`, use these holiday names: `New Year's Day`, `First Day of Ramadan`, `Eid al-Fitr`, `Easter Monday`, `Independence Day`, `Labor Day`, `Ascension Day`, `Eid al-Adha`, `Whit Monday`, `Martyrs' Day`, `Assumption Day`, `Anniversary of the Failed Attack on Lomé`, `All Saints' Day`, and `Christmas Day`.

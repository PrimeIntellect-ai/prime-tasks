Add SX Sint Maarten holidays
URLs:
 - https://en.wikipedia.org/wiki/Sint_Maarten
 - https://en.wikipedia.org/wiki/Public_holidays_in_Sint_Maarten
 - https://www.qppstudio.net/public-holidays/sint_maarten.htm
 - https://en.wikipedia.org/wiki/Public_holidays_in_Sint_Maarten
 - https://www.sintmaartengov.org/Pages/Public-Holiday-Schedule.aspx

### Additional contract requirements

- Add a public class `SintMaarten` in the module `holidays.countries.sint_maarten`, together with the public aliases `SX` and `SXM`, which are subclasses of `SintMaarten`.
- The default language is Dutch (`nl`). The public holiday names in Dutch are:
  - New Year's Day: `Nieuwjaarsdag`
  - Good Friday: `Goede Vrijdag`
  - Easter Sunday: `Eerste paasdag`
  - Easter Monday: `Tweede paasdag`
  - Queen's Day (until 2013): `Koninginnedag`
  - King's Day (from 2014): `Koningsdag`
  - Carnival Day: `Carnavalsdag`
  - Labor Day: `Dag van de Arbeid`
  - Ascension Day: `Hemelvaartsdag`
  - Whit Sunday: `Eerste Pinksterdag`
  - Emancipation Day: `Dag van de Bevrijding`
  - Constitution Day: `Dag van de Constitutie`
  - Sint Maarten Day: `Sint-Maartensdag`
  - Kingdom Day (until 2014): `Koninkrijksdag`
  - Christmas Day: `Eerste Kerstdag`
  - Second Day of Christmas: `Tweede Kerstdag`
- The `en_US` translations of these names are:
  - `Nieuwjaarsdag`: `New Year's Day`
  - `Goede Vrijdag`: `Good Friday`
  - `Eerste paasdag`: `Easter Sunday`
  - `Tweede paasdag`: `Easter Monday`
  - `Koninginnedag`: `Queen's Day`
  - `Koningsdag`: `King's Day`
  - `Carnavalsdag`: `Carnival Day`
  - `Dag van de Arbeid`: `Labor Day`
  - `Hemelvaartsdag`: `Ascension Day`
  - `Eerste Pinksterdag`: `Whit Sunday`
  - `Dag van de Bevrijding`: `Emancipation Day`
  - `Dag van de Constitutie`: `Constitution Day`
  - `Sint-Maartensdag`: `Sint Maarten Day`
  - `Koninkrijksdag`: `Kingdom Day`
  - `Eerste Kerstdag`: `Christmas Day`
  - `Tweede Kerstdag`: `Second Day of Christmas`
- The constructor accepts the standard holiday arguments and, when `observed_rule` is not supplied, defaults it to `SUN_TO_NEXT_MON`.
- No holidays are produced for years before 2011.

- Generate holidays on these calendar dates and apply the stated date adjustments:
  - New Year's Day is January 1; Good Friday, Easter Sunday, Easter Monday, Ascension Day, and Whit Sunday fall on their corresponding dates relative to Easter.
  - Queen's Day is April 30 through 2013, moving to the preceding Saturday when it falls on Sunday. King's Day is April 27 from 2014, also moving to the preceding Saturday when it falls on Sunday.
  - Carnival Day is April 29 through 2013. From 2014 it is April 30, moved to the preceding Friday if that date is Saturday, or to the following Tuesday if it is Sunday.
  - Labor Day is May 1. Emancipation Day is July 1 beginning in 2012, Constitution Day is the second Monday in October beginning in 2015, and Sint Maarten Day is November 11.
  - Kingdom Day is December 15 through 2014. Christmas Day and the Second Day of Christmas are December 25 and 26.
  - Emancipation Day and Kingdom Day are observed on the following Monday when their stated date falls on Sunday under the default observed rule. The Sunday adjustments stated above for Queen's Day, King's Day, and Carnival Day apply instead to those holidays.

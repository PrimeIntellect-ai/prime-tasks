Support Thunderstorm and Next-Week Properties in Dutch
In the near future, the API will begin generating the following new properties:

*   `possible-thunderstorm`
*   `thunderstorm`
*   `next-sunday`
*   `next-monday`
*   `next-tuesday`
*   `next-wednesday`
*   `next-thursday`
*   `next-friday`
*   `next-saturday`

Add support for these properties to Dutch. (Information is available in the README, and examples are visible in `/lib/lang/en.js` and `/test_cases/en.js`.)

### Additional contract requirements

- In Dutch, a title made from `possible-thunderstorm` reads `Mogelijk onweer`.
- In Dutch, a title made from `["and", "heavy-rain", "thunderstorm"]` reads `Zware regenbuien en onweer`.
- In Dutch, a title made from `next-sunday`, `next-monday`, `next-tuesday`, `next-wednesday`, `next-thursday`, `next-friday` or `next-saturday` reads `Volgende zondag`, `Volgende maandag`, `Volgende dinsdag`, `Volgende woensdag`, `Volgende donderdag`, `Volgende vrijdag` or `Volgende zaterdag` respectively.

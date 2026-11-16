Support Thunderstorm and Next-Week Properties in Polish
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

Add support for these properties to Polish. (Information is available in the README, and examples are visible in `/lib/lang/en.js` and `/test_cases/en.js`.)

### Additional contract requirements

- For the expression `["title", ["and", "heavy-rain", "thunderstorm"]]`, the exact output must be `Ulewa, burza`.

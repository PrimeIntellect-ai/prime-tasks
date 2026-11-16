Support Thunderstorm and Next-Week Properties in German
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

Add support for these properties to German. (Information is available in the README, and examples are visible in `/lib/lang/en.js` and `/test_cases/en.js`.)

### Additional contract requirements

- The German translation of `possible-thunderstorm` is `mögliche Gewitter`.
- The German translation of `thunderstorm` is `Gewitter`.
- The German translation of `next-sunday` is `am nächsten Sonntag`.
- The German translation of `next-monday` is `am nächsten Montag`.
- The German translation of `next-tuesday` is `am nächsten Dienstag`.
- The German translation of `next-wednesday` is `am nächsten Mittwoch`.
- The German translation of `next-thursday` is `am nächsten Donnerstag`.
- The German translation of `next-friday` is `am nächsten Freitag`.
- The German translation of `next-saturday` is `am nächsten Samstag`.
- The German translation of `["sentence",["until","possible-thunderstorm","next-wednesday"]]` must be exactly `Mögliche Gewitter bis am nächsten Mittwoch.`
- - The German translation of `["sentence",["until","thunderstorm","next-sunday"]]` must be exactly `Gewitter bis am nächsten Sonntag.`
- The German translation of `["sentence",["until","thunderstorm","next-monday"]]` must be exactly `Gewitter bis am nächsten Montag.`
- The German translation of `["sentence",["until","thunderstorm","next-tuesday"]]` must be exactly `Gewitter bis am nächsten Dienstag.`
- The German translation of `["sentence",["until","thunderstorm","next-thursday"]]` must be exactly `Gewitter bis am nächsten Donnerstag.`
- The German translation of `["sentence",["until","thunderstorm","next-friday"]]` must be exactly `Gewitter bis am nächsten Freitag.`
- The German translation of `["sentence",["until","thunderstorm","next-saturday"]]` must be exactly `Gewitter bis am nächsten Samstag.`

Support Thunderstorm and Next-Week Properties in Spanish
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

Add support for these properties to Spanish. (Information is available in the README, and examples are visible in `/lib/lang/en.js` and `/test_cases/en.js`.)

### Additional contract requirements

The Spanish summary text for each new property must be exactly:

*   `possible-thunderstorm`: "tormentas posibles"
*   `thunderstorm`: "tormenta"
*   `next-sunday`: "el próximo Domingo"
*   `next-monday`: "el próximo Lunes"
*   `next-tuesday`: "el próximo Martes"
*   `next-wednesday`: "el próximo Miércoles"
*   `next-thursday`: "el próximo Jueves"
*   `next-friday`: "el próximo Viernes"
*   `next-saturday`: "el próximo Sábado"

Translating the summary `["sentence", ["until", "possible-thunderstorm", "next-wednesday"]]` must produce exactly "Tormentas posibles hasta el próximo Miércoles.", using the existing Spanish sentence and "until" conventions.

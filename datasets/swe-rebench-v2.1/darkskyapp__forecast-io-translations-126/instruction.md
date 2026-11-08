Support Thunderstorm and Next-Week Properties in French
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

Add support for these properties to French. (Information is available in the README, and examples are visible in `/lib/lang/en.js` and `/test_cases/en.js`.)

### Additional contract requirements

- For the expression ["sentence",["during","possible-thunderstorm",["and","next-wednesday","next-thursday"]]], produce exactly "Orages possibles mercredi prochain et jeudi prochain."
- The French translation for `thunderstorm` is `orage`.
- The French translation for `next-sunday` is `dimanche prochain`, for `next-monday` is `lundi prochain`, for `next-tuesday` is `mardi prochain`, for `next-friday` is `vendredi prochain`, and for `next-saturday` is `samedi prochain`.

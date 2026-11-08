Update address provider for `en_IN`
* Faker version: 26.0.0
* OS: all

The address provider only have basic info on states. PIN Codes and union territories aren't added in the provider

### Additional contract requirements

- `pincode_in_state(state_abbr=...)` returns a PIN code within the numeric range defined for the supplied state abbreviation. The defined ranges include:
  - `GA`: 403000–403999
  - `TN`: 600000–669999
- The `en_IN` address provider exposes `union_territory()`, which generates the name of an Indian union territory.
- `pincode_in_military()` and its aliases generate a code in the Army Postal Service range 900000–999999. The aliases are `pincode_in_army()`, `zipcode_in_army()`, `postcode_in_army()`, `zipcode_in_military()`, and `postcode_in_military()`.

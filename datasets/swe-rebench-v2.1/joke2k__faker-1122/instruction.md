Faker missing french licence plate
I noticed that Faker was missing the implementation of French licence plates.
I would interested in adding this new feature :)

### Additional contract requirements

- With the `fr_FR` locale, `license_plate()` returns a French vehicle registration plate: either the current format `AA-123-AA` (two uppercase letters, three digits, two uppercase letters, separated by hyphens) or the older format `123-AAA-12` (three digits, three uppercase letters, two digits).
- The result is a string.

fix: location_ids and buildingCatalogue are inconsistent
Continuing the saga from #784 and #779, `location_ids` and `buildingCatalogue` are inconsistent.

Noted in #855:
> Not all locations are recognized for custom events on the map even though they are for classes (BS3, for example) and some don't even read on the calendar

In the particular case above,

buildingCatalogue:
```ts
    83057: {
        name: 'Biological Sciences III (BS3)',
        lat: 33.645363,
        lng: -117.846222,
        imageURLs: ['463/biological-sciences-iii.jpg'],
    },

    114877: {
        name: 'Biological Sciences III (BS3)',
        lat: 33.645363,
        lng: -117.846222,
        imageURLs: ['463/biological-sciences-iii.jpg'],
    },
```

location_ids:
```ts
    BS3: 114877,
```

Custom Events seemingly use the 83057 which don't exist in `location_ids`, whereas course events use 114877 which do.

### Additional contract requirements

- `location_ids` maps each building's short identifier to that building's numeric id in `buildingCatalogue`. The short identifier is the abbreviation shown in parentheses in the catalogue display name (e.g. `'Biological Sciences III (BS3)'` -> `BS3`); when a display name has no parenthesized abbreviation, the full display name is used as the identifier.
- Every key in `location_ids` must resolve, through its numeric id, to a `buildingCatalogue` entry whose short identifier equals that key.
- Every `buildingCatalogue` entry's short identifier must be a key in `location_ids`.

Color duplicates reporting should follow format of other reports
The color duplicates report is now a single array of objects, but for other reports of similar types we have an object with `total`, `totalUnique` and `unique`. For duplicates `total` and `totalUnique` will always be the same, since it is extracted from `colors.unique`.
Currently the `total` or `totalUnique` property is missing, so it is not easy to display it in Wallace-CLI, on projectwallace.com or to test for it easily in Gromit-CLI.

## Current format:
```json
"duplicates": [
  {
    "value": "#000",
    "count": 2,
    "aliases": [
    {
      "count": 1,
      "value": "#000"
    },
    {
      "count": 1,
      "value": "black"
    }]
  }
]
```

## Proposed format:
```json
"duplicates": {
  "total": 1,
  "totalUnique": 1,
  "unique": [
    {
      "value": "#000",
      "count": 2,
      "aliases": [
      {
        "count": 1,
        "value": "#000"
      },
      {
        "count": 1,
        "value": "black"
      }]
    }
  ]
}
```

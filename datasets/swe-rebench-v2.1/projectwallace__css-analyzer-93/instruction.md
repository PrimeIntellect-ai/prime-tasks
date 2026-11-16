analyze box-shadows
Also important for branding

### Additional contract requirements

- Provide a public function `analyze(declarations)` in module `src/analyzer/values/box-shadows.js`.
- `declarations` is an array of objects shaped `{ property: string, value: string }`. Only entries whose `property` is exactly `box-shadow` are considered.
- The function returns an object `{ total: number, unique: Array<{ value: string, count: number }>, totalUnique: number }`:
  - `total` is the number of `box-shadow` declarations processed.
  - `unique` contains one entry per distinct `box-shadow` value string, with `count` being the number of times that exact value appeared.
  - `totalUnique` is the number of distinct `box-shadow` values.
- The aggregate analysis output exposes this result at `values.boxshadows`. When there are no `box-shadow` declarations it is `{ total: 0, unique: [], totalUnique: 0 }`.

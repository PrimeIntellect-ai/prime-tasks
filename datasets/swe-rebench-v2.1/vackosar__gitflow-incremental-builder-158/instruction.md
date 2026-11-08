Changed non-reactor module is wrongly mapped to the closest reactor module
Given the following project layout:
- `root`
  - `A`
  - `B`

and given that `B` is changed, but is _not_ part of the reactor (e.g. profile activated `modules` in `root`), then `root` is considered changed, which is clearly wrong.

### Additional contract requirements

- When ignoring a changed file in a non-reactor module, emit a warning containing `[WARNING] Ignoring changed file in non-reactor module: `.

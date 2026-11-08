Ability to set aspectRatio
**Before you submit:**

- [x] Please search through the existing issues (both open AND closed) to see if your feature has already been discussed. Github issue search can be used for this: https://github.com/imgix/react-imgix/issues?utf8=%E2%9C%93&q=is%3Aissue
- [x] Please take a moment to find out whether your idea fits with the scope and aims of the project

**Is your feature request related to a problem? Please describe.**
It's currently impossible to maintain the aspect ratio correctly when using `srcSet` and `sizes`.
A lot of the other Imgix libraries support the ability to set the aspectRatio or handle aspectRatio in their calculations.

**Describe the solution you'd like**
An `aspectRatio` prop and for srcSets to respect the supplied aspect ratio.

### Additional contract requirements

- The aspect ratio is supplied through the `imgixParams` prop as the key `ar`, given as a string in `"width:height"` format (for example `"16:9"`). Each dimension may be an integer or a decimal number (for example `"1.92:1"` or `"1:1.67"`).
- When a valid `ar` is supplied and no explicit `height` is set, every `srcSet` candidate URL includes an `h` query parameter equal to `Math.ceil(width / arDecimal)`, where `arDecimal` is the numeric ratio `width / height` derived from `ar`.
- When `ar` is missing or is not in the valid format, the `h` parameter is omitted from the `srcSet` candidates.
- The rendered `src` URL never contains the `ar` parameter.
- All `imgixParams` keys other than `ar` are passed through to Imgix unchanged.
- When `ar` is present but not in the valid format, a warning is emitted through `console.warn`. This warning is controlled by the public config API exported from `react-imgix`: it can be turned off with `PublicConfigAPI.disableWarning("invalidARFormat")` and turned back on with `PublicConfigAPI.enableWarning("invalidARFormat")`.

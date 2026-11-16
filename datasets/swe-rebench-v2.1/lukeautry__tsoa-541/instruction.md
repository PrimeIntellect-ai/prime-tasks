Validation: Set defaults for optional params
<!--- Provide a general summary of the issue in the Title above -->

## Sorting

* **I'm submitting a ...**
  - [x] bug report
  - [ ] feature request
  - [ ] support request

* I confirm that I
  - [x] used the [search](https://github.com/lukeautry/tsoa/search?type=Issues) to make sure that a similar issue hasn't already been submit

## Expected Behavior
```
interface WithDefaults {
  /**
   * @isInt
   * @default 666
   */
  myNumber?: number;
}
```
sets 666 when no number gets sent in.

## Current Behavior
Generated metadata is correct, however, nothing is set during validation.

This happens because tsoa only sets defaults for required parameters (there is an explicit check).

## Possible Solution
Should set the default if `undefined`

## Breaking change?
potentially

This might apply for other validations aswell.

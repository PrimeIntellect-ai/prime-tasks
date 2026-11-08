Empty string among union values causes union to be resolved as 'any' instead of 'string'
Unions `type YesNo = "Yes" | "No" | ""` will have swagger generated with type object, as typeResolver produces 'any' data type.

## Sorting

* **I'm submitting a ...**
  - [x] bug report
  - [ ] feature request
  - [ ] support request

* I confirm that I
  - [x] used the [search](https://github.com/lukeautry/tsoa/search?type=Issues) to make sure that a similar issue hasn't already been submit

## Expected Behavior
Generates a swagger type enum and all its values

## Current Behavior
Generates a swagger type object

## Possible Solution
<!--- Not obligatory, but suggest a fix/reason for the bug, -->

## Steps to Reproduce
Generate swagger for `type YesNo = "Yes" | "No" | ""`

## Context (Environment)
Version of the library: 2.5.7
Version of NodeJS: 8
* Confirm you were using yarn not npm: [ ]

## Breaking change?
Potentially, as people may rely on empty strings to not produce correct swagger enum. Having empty strings in enums is very rare though.

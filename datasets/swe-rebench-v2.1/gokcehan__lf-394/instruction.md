Regression: [count]space doesn't work as expected after merging with the last PR ('fixed toggle behaviour')
For example `3<space>` only selects the current file and moves cursor one file down.

### Additional contract requirements

- For a positive prefix count N, `[count]space` should behave like N consecutive presses of `<space>`: each press toggles the selection of the current file and advances the cursor one file down. Thus `3<space>` performs that action three times, not once.
- A count of zero or less performs no action.

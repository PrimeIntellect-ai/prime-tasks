Ability to hide `Number of items closed` Metric in the overview table
### Is your feature request related to a problem?

`Number of items closed` as shown in the screenshot does not have any meaningful value when running the action against Discussions. Discussions are normally marked as answered rather than closed.

![Image](https://github.com/github/issue-metrics/assets/6935431/f703f710-96de-4584-9b5e-8f8ccb7cbdd0)



### Describe the solution you'd like

I would like to have the ability to configure `HIDE_ITEMS_CLOSED_COUNT` env variable such that it is not reported in the markdown output.

### Describe alternatives you've considered

Just dealing with it 🤷

### Additional context

_No response_

### Additional contract requirements

- When `HIDE_ITEMS_CLOSED_COUNT` is set to `true`, the overall metrics table in the generated Markdown report does not contain a "Number of items closed" row. All other rows stay as they are.
- When `HIDE_ITEMS_CLOSED_COUNT` is set to `false` or is unset, the "Number of items closed" row is shown as it is today.
- The configuration object returned by `get_env_vars()` exposes the parsed setting as the attribute `hide_items_closed_count` (boolean, `False` when unset).
- The Markdown writer function `write_to_markdown` accepts a keyword argument `hide_items_closed_count` (default `False`) with the same effect on the overall metrics table.

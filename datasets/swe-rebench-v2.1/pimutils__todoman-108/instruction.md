Use "tomorrow" and "today" when formatting date
When a todo expires today, or tomorrow, show "today" or "tomorrow" respectively instead of the actual date.

### Additional contract requirements

- The friendly labels are rendered in title case: `"Today"` for the current day and `"Tomorrow"` for the following day (not lowercase).
- Each label is padded on the left (right-justified) with spaces so that it occupies the same width as a regularly formatted date, keeping columns aligned.
- When no date is present (a falsy value such as `None` or `""`), the formatter returns a placeholder made of spaces of that same width.

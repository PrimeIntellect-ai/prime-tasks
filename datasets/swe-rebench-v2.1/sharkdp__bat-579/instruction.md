Output looks unbalanced when using '--style=grid,numbers' without 'header'.
The output looks a bit unbalanced when it's only printing the bottom horizontal line.

![image](https://user-images.githubusercontent.com/32112321/58363004-f0918f00-7e52-11e9-998c-836be74c1662.png)

Would it make more sense to only print that final horizontal line when the `header` component is enabled?

### Additional contract requirements

- For grid output without `header`, begin the output with a horizontal border before the first content line. In the tested layouts, that line is `────────────────────────────────────────────────────────────────────────────────` for plain grid output, `─────┬──────────────────────────────────────────────────────────────────────────` for numbered grid output, `──┬─────────────────────────────────────────────────────────────────────────────` for change-grid output, and `───────┬────────────────────────────────────────────────────────────────────────` for numbered change-grid output.

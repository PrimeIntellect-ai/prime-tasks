feat: method to expand to fill height tea.WithAltScreen()
Hello -- awesome library. I'm looking to use this with `tea.WithAltScreen()`, however I'm struggling to figure out the best approach to have the table expand to fill the entire height. This is the current layout of my UI (ignore the broken background):

![](https://cdn.liam.sh/share/2022/07/WindowsTerminal_22gIjsLZhT.png)

I'd essentially like the outer border to expand towards the bottom like shown below, however I don't see any height fields exposed to allow such a configuration.

![](https://cdn.liam.sh/share/2022/07/WindowsTerminal_1uxdiNGkjQ.png)

My first two thoughts would be:

1. An empty row, with no column dividers (and depending on if footer is enabled, the borders would be rounded).
2. A flag for toggling outer borders, but still allowing inner borders. This could allow the user to draw their own border. Currently, toggling border settings seems to apply across the board, including all columns/rows.

Thoughts? Is there another way that I'm missing to do this? I've thought about repurposing the footer, and dynamically changing the height of it, but that feels fragile given the dynamic height of some of the other components inside of the table.

### Additional contract requirements

Expose `Model.WithMinimumHeight(minimumHeight int) Model` to set a minimum total height for the rendered table, counting every rendered line including the header, body, footer, and outer borders. When the table's content is shorter, rendering must add empty body space so the table reaches at least that height without removing or changing its existing content, header, or footer. A table whose content already makes it taller than the requested minimum must remain untruncated.

[BUG] Rich markdown printed to console only shows a single link in a column/ table cell
- [x] I've checked [docs](https://rich.readthedocs.io/en/latest/introduction.html) and [closed issues](https://github.com/Textualize/rich/issues?q=is%3Aissue+is%3Aclosed) for possible solutions.
- [x] I can't find my issue in the [FAQ](https://github.com/Textualize/rich/blob/master/FAQ.md).

**Describe the bug**

I use Rich to format a pandas data frame with multiple links in some column to markdown and show it in the terminal. However, when there are more than a single link in a column rich only shows the last one?

```python
from rich.console import Console
from rich.markdown import Markdown

import pandas as pd

md_table = pd.DataFrame(
    {
        "links": ["[page1](https://www.example.com/page1), [page2](https://www.example.com/page2)"]
    }
).to_markdown()

console = Console()
console.print(Markdown(md_table))
```

Output:
```bash
      links
 ━━━━━━━━━━━
  0   page2
```

Expected
```
      links
 ━━━━━━━━━━━
  0   page1, page2
```

If I write the markdown to a file I get the expected table with multiple links...

**Platform**

platform="Darwin"
rich==13.5.2


</details>

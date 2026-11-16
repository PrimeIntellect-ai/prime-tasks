Cannot handle message data with date type
Example using plotly 6:

```python
from datetime import date, datetime
import polars as pl
import plotly.express as px
from plotly.graph_objs import FigureWidget

df=pl.DataFrame({'x': [date(2025, 1, 1), date(2025, 1, 2)], 'y': [1, 2]})
fig=px.line(df, x='x', y='y')

fig.show() # renders correctly

FigureWidget(fig).show() # fails
```

The last line results in:

```
ValueError: Can't clean for JSON: datetime.date(2025, 1, 1)
```

coming from
```
File ~/dev/jupyter_client/jupyter_client/jsonutil.py:195, in json_clean(obj)
    [HIDDEN]
```

### Additional contract requirements

- `jupyter_client.jsonutil.json_default` must serialize `datetime.date` values to their ISO 8601 date string, so `datetime.date(2025, 4, 8)` becomes `"2025-04-08"`, instead of raising `TypeError`.
- `jupyter_client.jsonutil.json_clean` must clean `datetime.date` values into a JSON-serializable string containing the date, so `datetime.date(2025, 4, 8)` yields a string containing `2025-04-08`, instead of raising `ValueError`.

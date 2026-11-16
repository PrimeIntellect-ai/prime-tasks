PercentTrue calculation can fail on BooleanNullable inputs when there are no values to aggregate
PercentTrue calculation can fail on BooleanNullable inputs when there are no values to aggregate

#### Code Sample, a copy-pastable example to reproduce your bug.

```python
import featuretools as ft
import pandas as pd
from woodwork.logical_types import BooleanNullable

es = ft.EntitySet(id="customer_data")

customers_df = pd.DataFrame(data={"customer_id": [1, 2]})

es = es.add_dataframe(
    dataframe_name="customers_df",
    dataframe=customers_df,
    index="customer_id",
)

transactions_df = pd.DataFrame(data={"tx_id": [1], "customer_id": [1], "is_foo": [True]})

es = es.add_dataframe(
    dataframe_name="transactions_df",
    dataframe=transactions_df,
    index="tx_id",
    logical_types={"is_foo": BooleanNullable}
)

es = es.add_relationship("customers_df", "customer_id", "transactions_df", "customer_id")

feature_matrix, features_definitions = ft.dfs(
    entityset=es,
    target_dataframe_name="customers_df",
    agg_primitives=["percent_true"],
)

```

[HIDDEN]

### Additional contract requirements

- When a PercentTrue aggregation over a BooleanNullable column has no values to aggregate, it must complete and yield a missing result (pd.NA), rather than fail or return zero.

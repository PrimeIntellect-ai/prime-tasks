[Bug]: Missing handling for `Iterator[IntoExpr]`
### Describe the bug

Discovered this in (https://github.com/vega/altair/pull/3631#discussion_r1934313255) and managed to narrow it down to a more minimal repro.

I think this may be an issue for any function that accepts `Iterable[IntoExpr]` but assumes `Sequence[IntoExpr]`.

I discovered a similar bug in `polars` a while back, but that was more limited in scope
- https://github.com/pola-rs/polars/pull/16254


So far I've found this impacts these two:

- `nw.all_horizontal`
- `nw.any_horizontal`

[HIDDEN]

https://github.com/narwhals-dev/narwhals/blob/f644931076307b150c1f1333c48835e4ffe9342c/narwhals/utils.py#L344-L349

### Steps or code to reproduce the bug

```py
from __future__ import annotations  # noqa: F404

from collections.abc import Iterable, Iterator
from typing import Any

import polars as pl
from narwhals.stable import v1 as nw


def iter_eq(namespace: Any, items: Iterable[tuple[str, Any]], /) -> Iterator[Any]:
    for column, value in items:
        yield namespace.col(column) == value


def any_horizontal(namespace: Any, items: Iterable[tuple[str, Any]], /) -> Any:
    expr = iter_eq(namespace, items)
    return namespace.any_horizontal(expr)


pl_frame = pl.DataFrame({"A": range(5), "B": list("bbaab")})
nw_frame = nw.from_native(pl_frame, eager_only=True)

expr_items = [("A", 3), ("B", "b")]
nw_expr = any_horizontal(nw, expr_items)

nw_one = nw_frame.filter(nw_expr)
>>> nw_frame.filter(nw_expr)
```

### Expected results

No error is thrown.

Using the same example in `polars`, the same expression can be used multiple times **regardless** of the kind of `Iterable` used.

```py
pl_expr = any_horizontal(pl, expr_items)
pl_results = (
    pl_frame.filter(pl_expr),
    pl_frame.filter(pl_expr),
    pl_frame.filter(~pl_expr),
    pl_frame.filter(~~pl_expr),
)
>>> pl_results
```

#### Output
```py
(shape: (4, 2)
 ┌─────┬─────┐
 │ A   ┆ B   │
 │ --- ┆ --- │
 │ i64 ┆ str │
 ╞═════╪═════╡
 │ 0   ┆ b   │
 │ 1   ┆ b   │
 │ 3   ┆ a   │
 │ 4   ┆ b   │
 └─────┴─────┘,
 shape: (4, 2)
 ┌─────┬─────┐
 │ A   ┆ B   │
 │ --- ┆ --- │
 │ i64 ┆ str │
 ╞═════╪═════╡
 │ 0   ┆ b   │
 │ 1   ┆ b   │
 │ 3   ┆ a   │
 │ 4   ┆ b   │
 └─────┴─────┘,
 shape: (1, 2)
 ┌─────┬─────┐
 │ A   ┆ B   │
 │ --- ┆ --- │
 │ i64 ┆ str │
 ╞═════╪═════╡
 │ 2   ┆ a   │
 └─────┴─────┘,
 shape: (4, 2)
 ┌─────┬─────┐
 │ A   ┆ B   │
 │ --- ┆ --- │
 │ i64 ┆ str │
 ╞═════╪═════╡
 │ 0   ┆ b   │
 │ 1   ┆ b   │
 │ 3   ┆ a   │
 │ 4   ┆ b   │
 └─────┴─────┘)
```

### Actual results

No results, see **Relevant log output**


### Please run narwhals.show_version() and enter the output below.

```shell
System:
    python: 3.12.8 (main, Dec 19 2024, 14:41:01) [MSC v.1942 64 bit (AMD64)]
executable: c:\Users\danie\Documents\GitHub\altair\.venv\Scripts\python.exe
   machine: Windows-10-10.0.19045-SP0

Python dependencies:
     narwhals: 1.22.0
       pandas: 2.2.3
       polars: 1.20.0
         cudf:
        modin:
      pyarrow: 19.0.0
        numpy: 2.2.1
```

### Relevant log output

```shell
---------------------------------------------------------------------------
ComputeError                              Traceback (most recent call last)
Cell In[20], line 2
      1 nw_one = nw_frame.filter(nw_expr)
----> 2 nw_frame.filter(nw_expr)

File c:\Users\danie\Documents\GitHub\altair\.venv\Lib\site-packages\narwhals\dataframe.py:2317, in DataFrame.filter(self, *predicates, **constraints)
   2136 def filter(
   2137     self, *predicates: IntoExpr | Iterable[IntoExpr] | list[bool], **constraints: Any
   2138 ) -> Self:
   2139     r"""Filter the rows in the DataFrame based on one or more predicate expressions.
   2140
   2141     The original order of the remaining rows is preserved.
   (...)
   2315         ham: [["b"]]
   2316     """
-> 2317     return super().filter(*predicates, **constraints)

File c:\Users\danie\Documents\GitHub\altair\.venv\Lib\site-packages\narwhals\dataframe.py:158, in BaseFrame.filter(self, *predicates, **constraints)
    150 def filter(
    151     self, *predicates: IntoExpr | Iterable[IntoExpr] | list[bool], **constraints: Any
    152 ) -> Self:
    153     if not (
    154         len(predicates) == 1
    155         and isinstance(predicates[0], list)
    156         and all(isinstance(x, bool) for x in predicates[0])
    157     ):
--> 158         predicates, constraints = self._flatten_and_extract(
    159             *predicates, **constraints
    160         )
    161     return self._from_compliant_dataframe(
    162         self._compliant_frame.filter(*predicates, **constraints),
    163     )

File c:\Users\danie\Documents\GitHub\altair\.venv\Lib\site-packages\narwhals\dataframe.py:68, in BaseFrame._flatten_and_extract(self, *args, **kwargs)
     66 def _flatten_and_extract(self, *args: Any, **kwargs: Any) -> Any:
     67     """Process `args` and `kwargs`, extracting underlying objects as we go."""
---> 68     args = [self._extract_compliant(v) for v in flatten(args)]  # type: ignore[assignment]
     69     kwargs = {k: self._extract_compliant(v) for k, v in kwargs.items()}
     70     return args, kwargs

File c:\Users\danie\Documents\GitHub\altair\.venv\Lib\site-packages\narwhals\dataframe.py:81, in BaseFrame._extract_compliant(self, arg)
     79     return arg._compliant_series
     80 if isinstance(arg, Expr):
---> 81     return arg._to_compliant_expr(self.__narwhals_namespace__())
     82 if get_polars() is not None and "polars" in str(type(arg)):
     83     msg = (
     84         f"Expected Narwhals object, got: {type(arg)}.\n\n"
     85         "Perhaps you:\n"
     86         "- Forgot a `nw.from_native` somewhere?\n"
     87         "- Used `pl.col` instead of `nw.col`?"
     88     )

File c:\Users\danie\Documents\GitHub\altair\.venv\Lib\site-packages\narwhals\functions.py:2371, in any_horizontal.<locals>.<lambda>(plx)
   2368     msg = "At least one expression must be passed to `any_horizontal`"
   2369     raise ValueError(msg)
   2370 return Expr(
-> 2371     lambda plx: plx.any_horizontal(
   2372         [HIDDEN]
   2373     )
   2374 )

File c:\Users\danie\Documents\GitHub\altair\.venv\Lib\site-packages\narwhals\_polars\namespace.py:43, in PolarsNamespace.__getattr__.<locals>.func(*args, **kwargs)
     40 def func(*args: Any, **kwargs: Any) -> Any:
     41     args, kwargs = extract_args_kwargs(args, kwargs)  # type: ignore[assignment]
     42     return PolarsExpr(
---> 43         getattr(pl, attr)(*args, **kwargs),
     44         version=self._version,
     45         backend_version=self._backend_version,
     46     )

File c:\Users\danie\Documents\GitHub\altair\.venv\Lib\site-packages\polars\functions\aggregation\horizontal.py:108, in any_horizontal(*exprs)
     67 """
     68 Compute the bitwise OR horizontally across columns.
     69
   (...)
    105 └───────┴───────┴─────┴───────┘
    106 """
    107 pyexprs = parse_into_list_of_expressions(*exprs)
--> 108 return wrap_expr(plr.any_horizontal(pyexprs))

ComputeError: cannot return empty fold because the number of output rows is unknown
```

### Additional contract requirements

- `nw.all_horizontal` and `nw.any_horizontal` must each accept a one-shot iterator or generator of expressions as a single argument, computing the horizontal conjunction and disjunction, respectively.
- An expression created from an iterator or generator must remain usable in repeated dataframe operations; consuming the input once must not cause later uses to behave as an empty expression.

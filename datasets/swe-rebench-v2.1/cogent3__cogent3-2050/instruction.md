ENH: extend support for bootstrap values from newick strings
`cogent3` stores support values (e.g. from a bootstrap) as `<phylonode>.params["support"]` entry. This information is also stored in some versions of newick strings. For example, IQTree uses `((a,b)##:0.1,..` and `((a,b)node_name/##:0.1,..` where `##` is an integer to record support measures. The current cogent3 parser treats both those values as name. We need to add code that correctly transforms these names into the name and support values.

To address this issue, write a function `split_name_and_support(field: str | None) -> tuple[str | None, float | None)` in `cogent3.core.tree`.

It should cope with them being either a name and no support, support and no name, or both. Specific cases are:

- field is `None` or an empty string, returns `None, None`
- field is `"edge.98/24"` returns `"edge.98", 24.0`
- field is `"edge.98"` returns `"edge.98", None`
- field is `"24"` returns `None, 24.0`

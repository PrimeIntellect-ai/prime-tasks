ENH: Support datetime64[ns, UTC}
Though utility in Tableau is limited this should be allowable

### Additional contract requirements

When UTC timestamp data is read back from a Hyper extract, its values must be preserved and its pandas dtype must be `datetime64[ns, UTC]`.
